import SwiftUI
import AVFoundation
import Combine
import FluidAudio

/// Central engine managing audio capture, pipeline processing, and state.
///
/// This is the main ObservableObject that coordinates:
/// - Audio capture with optional Voice Isolation
/// - VAD (FluidAudio Silero) → ASR (SenseVoice) → Speaker ID (x-vector) pipeline
/// - Self-improving speaker profiles (VoiceLibrary)
/// - UI state and metrics
@MainActor
class VoiceEngine: ObservableObject {
    // MARK: - Published State

    @Published var isRecording = false
    @Published var voiceIsolationEnabled = true
    @Published var transcripts: [TranscriptSegment] = []
    @Published var speakers: [SpeakerProfile] = []
    @Published var metrics = PipelineMetrics()
    @Published var modelStatus = ModelStatus()

    // Segments needing manual speaker tagging
    var untaggedSegments: [TranscriptSegment] {
        transcripts.filter { $0.speaker == nil }
    }

    // MARK: - Internal Components

    private var audioCapture: AudioCapture?
    private var voiceLibrary = VoiceLibrary()

    // CoreML Models
    private var vadManager: VadManager?
    private var senseVoice: SenseVoiceASR?
    private var xvector: XVectorEmbedding?

    // MARK: - Initialization

    init() {
        // Load saved speakers
        loadSpeakers()

        // Initialize models asynchronously
        Task {
            await loadModels()
        }

        // Add sample data for preview/testing
        #if DEBUG
        if speakers.isEmpty {
            addSampleData()
        }
        #endif
    }

    // MARK: - Model Loading

    private func loadModels() async {
        // Load FluidAudio VAD
        do {
            vadManager = try await VadManager()
            await MainActor.run { modelStatus.vadLoaded = true }
            print("FluidAudio VAD loaded successfully")
        } catch {
            print("Failed to load FluidAudio VAD: \(error)")
        }

        // Load SenseVoice ASR
        do {
            senseVoice = try SenseVoiceASR()
            await MainActor.run { modelStatus.asrLoaded = true }
        } catch {
            print("Failed to load SenseVoice: \(error)")
        }

        // Load x-vector embedding
        do {
            xvector = try XVectorEmbedding()
            await MainActor.run { modelStatus.speakerIdLoaded = true }
        } catch {
            print("Failed to load x-vector: \(error)")
        }
    }

    // MARK: - Recording Control

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        guard !isRecording else { return }

        Task {
            do {
                audioCapture = AudioCapture()
                try await audioCapture?.start(voiceIsolation: voiceIsolationEnabled) { [weak self] segment in
                    Task { @MainActor in
                        await self?.processSegment(segment)
                    }
                }
                isRecording = true
            } catch {
                print("Failed to start recording: \(error)")
            }
        }
    }

    func stopRecording() {
        audioCapture?.stop()
        audioCapture = nil
        isRecording = false
    }

    // MARK: - Pipeline Processing

    private func processSegment(_ segment: AudioSegment) async {
        let pipelineStart = Date()

        // Convert audio data to [Float]
        let audioSamples = segment.audioData.withUnsafeBytes { buffer -> [Float] in
            let floatBuffer = buffer.bindMemory(to: Float.self)
            return Array(floatBuffer)
        }

        // 1. VAD is already done in AudioCapture, just record timing
        let vadTime = Date()
        metrics.vadMs = Int(vadTime.timeIntervalSince(pipelineStart) * 1000)

        // 2. ASR - Transcribe with SenseVoice
        var text = "[No ASR model]"
        if let asr = senseVoice {
            let (transcribedText, asrMs) = asr.transcribeTimed(audioSamples)
            text = transcribedText ?? "[Transcription failed]"
            metrics.asrMs = Int(asrMs)
        }

        // 3. Speaker ID - Extract embedding and match
        let speakerIdStart = Date()
        var speaker: String? = nil
        var embedding: [Float]? = nil

        if let embedder = xvector {
            let (emb, embeddingMs) = embedder.extractEmbeddingTimed(from: audioSamples)

            if let emb = emb {
                embedding = emb
                let (matchedSpeaker, result) = voiceLibrary.identify(emb)

                if let matched = matchedSpeaker, result.confidence >= .medium {
                    speaker = matched

                    // Auto-learn if high confidence
                    if result.confidence == .high {
                        voiceLibrary.autoLearn(speaker: matched, embedding: emb)
                        metrics.autoLearnedCount += 1
                    }
                }
            }

            metrics.speakerIdMs = Int(embeddingMs)
        } else {
            metrics.speakerIdMs = Int(Date().timeIntervalSince(speakerIdStart) * 1000)
        }

        // Create transcript segment
        let transcript = TranscriptSegment(
            text: text,
            speaker: speaker,
            audioData: segment.audioData,
            embedding: embedding
        )

        transcripts.append(transcript)

        // Update speakers list from library
        speakers = voiceLibrary.allProfiles()

        // Update accuracy metric (simple estimate based on identified vs total)
        let identified = transcripts.filter { $0.speaker != nil }.count
        let total = transcripts.count
        if total > 0 {
            metrics.accuracy = Double(identified) / Double(total) * 100
        }
    }

    // MARK: - Speaker Management

    func addSpeaker(name: String) {
        guard !name.isEmpty else { return }

        // Create with placeholder embedding (will be updated on first tag)
        let placeholder = [Float](repeating: 0, count: 512)
        voiceLibrary.enroll(name: name, embedding: placeholder)
        speakers = voiceLibrary.allProfiles()
        saveSpeakers()
    }

    func tagSegment(_ segment: TranscriptSegment, as speakerName: String) {
        // Find and update the segment
        if let index = transcripts.firstIndex(where: { $0.id == segment.id }) {
            transcripts[index].speaker = speakerName

            // If segment has embedding, use it to improve the speaker profile
            if let embedding = segment.embedding {
                voiceLibrary.autoLearn(speaker: speakerName, embedding: embedding)
                speakers = voiceLibrary.allProfiles()
                saveSpeakers()
            }
        }
    }

    func promptNewSpeaker(for segment: TranscriptSegment) {
        // TODO: Show dialog to enter new speaker name
        // For now, just mark as "Unknown"
        tagSegment(segment, as: "Unknown")
    }

    // MARK: - Persistence

    private func saveSpeakers() {
        voiceLibrary.save(to: speakersFileURL)
    }

    private func loadSpeakers() {
        voiceLibrary.load(from: speakersFileURL)
        speakers = voiceLibrary.allProfiles()
    }

    private var speakersFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("YouPu", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)

        return appDir.appendingPathComponent("speakers.json")
    }

    // MARK: - Sample Data (Debug)

    #if DEBUG
    private func addSampleData() {
        // Add sample speakers for UI preview
        let sampleEmbedding = [Float](repeating: 0.1, count: 512)

        voiceLibrary.enroll(name: "Dad", embedding: sampleEmbedding)
        voiceLibrary.enroll(name: "Mom", embedding: sampleEmbedding.map { $0 + 0.1 })
        voiceLibrary.enroll(name: "Son", embedding: sampleEmbedding.map { $0 + 0.2 })

        speakers = voiceLibrary.allProfiles()

        // Add sample transcripts
        transcripts = [
            TranscriptSegment(timestamp: "14:32:01", text: "Hello, how are you today?", speaker: "Dad"),
            TranscriptSegment(timestamp: "14:32:03", text: "你好，今天怎么样？", speaker: "Mom"),
            TranscriptSegment(timestamp: "14:32:05", text: "I'm doing great, thanks!", speaker: "Son"),
            TranscriptSegment(timestamp: "14:32:08", text: "好的，我们待会儿见。", speaker: "Dad"),
            TranscriptSegment(timestamp: "14:32:10", text: "Something something...", speaker: nil),  // Untagged
        ]

        // Sample metrics
        metrics.vadMs = 2
        metrics.asrMs = 45
        metrics.speakerIdMs = 14
        metrics.accuracy = 94.2
        metrics.autoLearnedCount = 23
    }
    #endif
}

// MARK: - Audio Segment

struct AudioSegment {
    let audioData: Data
    let embedding: [Float]?
    let duration: TimeInterval
}

// MARK: - Model Status

struct ModelStatus {
    var vadLoaded = false
    var asrLoaded = false
    var speakerIdLoaded = false

    var allLoaded: Bool {
        vadLoaded && asrLoaded && speakerIdLoaded
    }
}
