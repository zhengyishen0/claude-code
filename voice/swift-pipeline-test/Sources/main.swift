#!/usr/bin/env swift
import Foundation
import CoreML
import Accelerate
import AVFoundation
import KissFFT
import SentencepieceTokenizer

// MARK: - Project Configuration

/// YouPu project root - absolute path for consistent access to models
/// Note: Models are .gitignored, so always reference the main repo location
let YOUPU_ROOT = "/Users/zhengyishen/Codes/claude-code/voice/YouPu"

// MARK: - Configuration (matches Python exactly)

let SAMPLE_RATE: Int = 16000
let SAMPLE_RATE_DOUBLE: Double = 16000.0
let XVECTOR_SAMPLES: Int = 48000  // 3 seconds for speaker embedding

// VAD Configuration (matches Python live.py)
let VAD_THRESHOLD: Float = 0.02        // RMS threshold for speech detection
let MIN_SPEECH_DURATION: Double = 0.3  // Minimum speech duration in seconds
let MIN_SILENCE_DURATION: Double = 0.5 // Silence duration to end speech segment
let CHUNK_SIZE: Int = 512              // ~32ms at 16kHz
let N_MELS: Int = 80
let N_FFT: Int = 400      // 25ms at 16kHz
let HOP_LENGTH: Int = 160 // 10ms at 16kHz
let LFR_M: Int = 7        // Stack 7 frames
let LFR_N: Int = 6        // Skip 6 frames
let FIXED_FRAMES: Int = 500

// Note: Python uses torchaudio.transforms.MelSpectrogram with power=1.0 (magnitude, not power)
// and NO CMVN normalization. Just: mel -> log -> LFR -> model

// MARK: - Speaker Identification

/// Two-layer speaker profile with core and boundary embeddings
/// Core: Frequent voice patterns (within 1σ of centroid)
/// Boundary: Edge case voice patterns (1σ to 2σ from centroid)
class SpeakerProfile {
    static let MAX_CORE = 5
    static let MAX_BOUNDARY = 10
    static let MIN_DIVERSITY: Float = 0.1

    let name: String
    var core: [[Float]] = []
    var boundary: [[Float]] = []
    var centroid: [Float]?
    var stdDev: Float = 0.2
    var allDistances: [Float] = []

    init(name: String, initialEmbedding: [Float]? = nil) {
        self.name = name
        if let emb = initialEmbedding {
            self.core.append(emb)
            self.centroid = emb
        }
    }

    private func updateCentroid() {
        guard !core.isEmpty else { return }
        let dim = core[0].count
        var sum = [Float](repeating: 0, count: dim)
        for emb in core {
            for i in 0..<dim {
                sum[i] += emb[i]
            }
        }
        centroid = sum.map { $0 / Float(core.count) }
    }

    private func updateStdDev() {
        guard allDistances.count >= 3 else { return }
        let mean = allDistances.reduce(0, +) / Float(allDistances.count)
        let variance = allDistances.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Float(allDistances.count)
        stdDev = max(sqrt(variance), 0.05)
    }

    private func isDiverseFrom(_ embedding: [Float], existing: [[Float]], minDist: Float) -> Bool {
        guard !existing.isEmpty else { return true }
        for e in existing {
            if cosineDistance(embedding, e) < minDist {
                return false
            }
        }
        return true
    }

    /// Add embedding to appropriate layer based on distance from centroid
    /// Returns: "core", "boundary", or "rejected"
    func addEmbedding(_ embedding: [Float], forceBoundary: Bool = false) -> String {
        guard let cent = centroid else {
            core.append(embedding)
            centroid = embedding
            return "core"
        }

        let dist = cosineDistance(embedding, cent)
        allDistances.append(dist)
        updateStdDev()

        if forceBoundary {
            if boundary.count < SpeakerProfile.MAX_BOUNDARY {
                if isDiverseFrom(embedding, existing: boundary, minDist: SpeakerProfile.MIN_DIVERSITY) {
                    boundary.append(embedding)
                    return "boundary"
                }
            }
            return "rejected"
        }

        if dist < 1.0 * stdDev {
            // Within 1σ → Core candidate
            if core.count < SpeakerProfile.MAX_CORE {
                if isDiverseFrom(embedding, existing: core, minDist: SpeakerProfile.MIN_DIVERSITY) {
                    core.append(embedding)
                    updateCentroid()
                    return "core"
                }
            }
            return "rejected"
        } else if dist < 2.0 * stdDev {
            // Between 1σ and 2σ → Boundary candidate
            if boundary.count < SpeakerProfile.MAX_BOUNDARY {
                if isDiverseFrom(embedding, existing: boundary, minDist: SpeakerProfile.MIN_DIVERSITY) {
                    boundary.append(embedding)
                    return "boundary"
                }
            }
            return "rejected"
        } else {
            // Beyond 2σ → Too far
            return "rejected"
        }
    }

    func maxSimilarityToCore(_ embedding: [Float]) -> Float {
        guard !core.isEmpty else { return 0 }
        return core.map { cosineSimilarity(embedding, $0) }.max() ?? 0
    }

    func maxSimilarityToBoundary(_ embedding: [Float]) -> Float {
        let allEmbs = core + boundary
        guard !allEmbs.isEmpty else { return 0 }
        return allEmbs.map { cosineSimilarity(embedding, $0) }.max() ?? 0
    }

    func toDict() -> [String: Any] {
        return [
            "core": core,
            "boundary": boundary,
            "centroid": centroid as Any,
            "std_dev": stdDev,
            "all_distances": Array(allDistances.suffix(100))
        ]
    }

    static func fromDict(name: String, data: [String: Any]) -> SpeakerProfile {
        let profile = SpeakerProfile(name: name)
        if let coreData = data["core"] as? [[Double]] {
            profile.core = coreData.map { $0.map { Float($0) } }
        } else if let coreData = data["core"] as? [[Float]] {
            profile.core = coreData
        }
        if let boundaryData = data["boundary"] as? [[Double]] {
            profile.boundary = boundaryData.map { $0.map { Float($0) } }
        } else if let boundaryData = data["boundary"] as? [[Float]] {
            profile.boundary = boundaryData
        }
        if let centroidData = data["centroid"] as? [Double] {
            profile.centroid = centroidData.map { Float($0) }
        } else if let centroidData = data["centroid"] as? [Float] {
            profile.centroid = centroidData
        }
        if let sd = data["std_dev"] as? Double {
            profile.stdDev = Float(sd)
        }
        if let dists = data["all_distances"] as? [Double] {
            profile.allDistances = dists.map { Float($0) }
        }
        return profile
    }
}

/// Persistent voice library with two-layer speaker profiles
class VoiceLibrary {
    static let BOUNDARY_THRESHOLD: Float = 0.35
    static let CORE_THRESHOLD: Float = 0.45
    static let AUTO_LEARN_THRESHOLD: Float = 0.55
    static let CONFLICT_MARGIN: Float = 0.1

    let path: String
    var speakers: [String: SpeakerProfile] = [:]

    init(path: String) {
        self.path = path
        load()
    }

    func load() {
        guard FileManager.default.fileExists(atPath: path),
              let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("  No voice library found at \(path)")
            return
        }

        for (name, value) in json {
            if let dict = value as? [String: Any], dict["core"] != nil {
                speakers[name] = SpeakerProfile.fromDict(name: name, data: dict)
            }
        }
        print("  Loaded \(speakers.count) speakers: \(Array(speakers.keys))")
    }

    func save() {
        var data: [String: Any] = [:]
        for (name, profile) in speakers {
            data[name] = profile.toDict()
        }
        if let jsonData = try? JSONSerialization.data(withJSONObject: data, options: .prettyPrinted) {
            try? jsonData.write(to: URL(fileURLWithPath: path))
        }
    }

    /// Two-phase matching: boundary first, then core if conflict
    /// Returns: (name, score, confidence) where confidence is "high", "medium", "low", or "conflict"
    func match(_ embedding: [Float], threshold: Float? = nil) -> (String?, Float, String) {
        guard !speakers.isEmpty else { return (nil, 0, "low") }

        let thresh = threshold ?? VoiceLibrary.BOUNDARY_THRESHOLD

        // Debug: print all similarity scores
        print("  Matching against \(speakers.count) speakers:")
        var allScores: [(String, Float)] = []
        for (name, profile) in speakers {
            let score = profile.maxSimilarityToBoundary(embedding)
            allScores.append((name, score))
        }
        allScores.sort { $0.1 > $1.1 }
        for (name, score) in allScores.prefix(3) {
            print("    \(name): \(String(format: "%.3f", score))")
        }

        // Phase 1: Check all boundary layers
        var boundaryMatches: [(String, Float, SpeakerProfile)] = []
        for (name, profile) in speakers {
            let score = profile.maxSimilarityToBoundary(embedding)
            if score >= thresh {
                boundaryMatches.append((name, score, profile))
            }
        }

        if boundaryMatches.isEmpty {
            return (nil, 0, "low")
        }

        if boundaryMatches.count == 1 {
            let (name, score, _) = boundaryMatches[0]
            let confidence = score >= VoiceLibrary.AUTO_LEARN_THRESHOLD ? "high" : "medium"
            return (name, score, confidence)
        }

        // Phase 2: Conflict - use core scores to distinguish
        var coreScores: [(String, Float, SpeakerProfile)] = []
        for (name, _, profile) in boundaryMatches {
            let coreScore = profile.maxSimilarityToCore(embedding)
            coreScores.append((name, coreScore, profile))
        }

        coreScores.sort { $0.1 > $1.1 }
        let (bestName, bestScore, _) = coreScores[0]
        let (secondName, secondScore, _) = coreScores[1]

        if bestScore - secondScore >= VoiceLibrary.CONFLICT_MARGIN {
            let confidence = bestScore >= VoiceLibrary.AUTO_LEARN_THRESHOLD ? "high" : "medium"
            return (bestName, bestScore, confidence)
        } else {
            return ("[\(bestName)/\(secondName)?]", bestScore, "conflict")
        }
    }

    func addEmbedding(_ name: String, _ embedding: [Float], forceBoundary: Bool = false) -> String {
        if speakers[name] == nil {
            speakers[name] = SpeakerProfile(name: name, initialEmbedding: embedding)
            save()
            return "core"
        }

        let result = speakers[name]!.addEmbedding(embedding, forceBoundary: forceBoundary)
        if result != "rejected" {
            save()
        }
        return result
    }

    func autoLearn(_ name: String, _ embedding: [Float], score: Float) -> Bool {
        if score >= VoiceLibrary.AUTO_LEARN_THRESHOLD, speakers[name] != nil {
            let result = speakers[name]!.addEmbedding(embedding)
            if result != "rejected" {
                save()
                return true
            }
        }
        return false
    }
}

// MARK: - Live Pipeline

/// Live voice pipeline with VAD-driven streaming (matches Python live.py)
class LivePipeline {
    // Models
    private var asrModel: MLModel?
    private var speakerModel: MLModel?
    private var tokenizer: SentencepieceTokenizer?
    private var voiceLibrary: VoiceLibrary?

    // Audio engine
    private var audioEngine: AVAudioEngine?
    private var audioConverter: AVAudioConverter?

    // VAD state (matches Python VADProcessor)
    private var speechBuffer: [Float] = []
    private var isSpeaking = false
    private var speechStartSample: Int = 0
    private var totalSamples: Int = 0
    private var silenceSamples: Int = 0

    // Processing
    private let processingQueue = DispatchQueue(label: "live.processing", qos: .userInitiated)
    private var isRunning = false
    private var segments: [[String: Any]] = []

    // Signal handling
    private var signalSource: DispatchSourceSignal?
    private let stopSemaphore = DispatchSemaphore(value: 0)

    // Configuration
    private var useVoiceIsolation: Bool = false

    init(voiceIsolation: Bool = false) {
        self.useVoiceIsolation = voiceIsolation
    }

    func loadModels() {
        print("\n📦 Loading models...")
        let startTotal = CFAbsoluteTimeGetCurrent()

        // Load ASR model
        var t0 = CFAbsoluteTimeGetCurrent()
        if let modelURL = findModel(named: "sensevoice-500-itn", ext: "mlmodelc") {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            asrModel = try? MLModel(contentsOf: modelURL, configuration: config)
            print("  ASR: \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - t0))s")
        }

        // Load speaker model
        t0 = CFAbsoluteTimeGetCurrent()
        if let speakerURL = findSpeakerModel() {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            speakerModel = try? MLModel(contentsOf: speakerURL, configuration: config)
            print("  Speaker (xvector, 512-dim): \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - t0))s")
        }

        // Load tokenizer
        t0 = CFAbsoluteTimeGetCurrent()
        if let tokenizerPath = findTokenizerModel() {
            tokenizer = try? SentencepieceTokenizer(modelPath: tokenizerPath)
            print("  Tokenizer: \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - t0))s")
        }

        // Load voice library
        t0 = CFAbsoluteTimeGetCurrent()
        if let libraryPath = findVoiceLibrary() {
            voiceLibrary = VoiceLibrary(path: libraryPath)
            print("  Voice Library: \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - t0))s")
        }

        print("  Total: \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - startTotal))s")
    }

    private func calculateRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
        return rms
    }

    private func processVADChunk(_ samples: [Float]) {
        totalSamples += samples.count

        let rms = calculateRMS(samples)

        if rms > VAD_THRESHOLD {
            // Speech detected
            silenceSamples = 0
            if !isSpeaking {
                // Speech started
                isSpeaking = true
                speechStartSample = totalSamples - samples.count
                speechBuffer = samples
            } else {
                // Speech continues
                speechBuffer.append(contentsOf: samples)
            }
        } else {
            // Silence detected
            if isSpeaking {
                silenceSamples += samples.count
                speechBuffer.append(contentsOf: samples)

                // Check if silence is long enough to end speech
                let silenceDuration = Double(silenceSamples) / SAMPLE_RATE_DOUBLE
                if silenceDuration >= MIN_SILENCE_DURATION {
                    // Speech ended
                    isSpeaking = false

                    // Check minimum duration
                    let speechDuration = Double(speechBuffer.count) / SAMPLE_RATE_DOUBLE
                    if speechDuration >= MIN_SPEECH_DURATION {
                        let segment = speechBuffer
                        let startTime = Double(speechStartSample) / SAMPLE_RATE_DOUBLE
                        let endTime = Double(speechStartSample + speechBuffer.count) / SAMPLE_RATE_DOUBLE

                        // Process segment in background
                        processingQueue.async { [weak self] in
                            self?.processSegment(audio: segment, startTime: startTime, endTime: endTime)
                        }
                    }

                    speechBuffer = []
                    silenceSamples = 0
                }
            }
        }
    }

    private func processSegment(audio: [Float], startTime: Double, endTime: Double) {
        guard let asrModel = asrModel, let speakerModel = speakerModel else { return }

        let startProcess = CFAbsoluteTimeGetCurrent()

        // Run transcription
        let transcription = transcribeAudioSegment(audio: audio, model: asrModel)

        // Run speaker identification
        var speakerName: String? = nil
        var speakerScore: Float = 0
        var speakerConfidence = "low"
        var learned = false

        if let embedding = extractSpeakerEmbedding(audio: audio, model: speakerModel),
           let library = voiceLibrary {
            let (name, score, confidence) = library.match(embedding)
            speakerName = name
            speakerScore = score
            speakerConfidence = confidence

            // Auto-learn from high-confidence matches
            if let matchedName = name, confidence == "high", !matchedName.hasPrefix("[") {
                learned = library.autoLearn(matchedName, embedding, score: score)
            }
        }

        let processTime = (CFAbsoluteTimeGetCurrent() - startProcess) * 1000

        // Skip empty transcriptions
        guard let text = transcription, !text.isEmpty else { return }

        // Format speaker label
        let speakerLabel: String
        if let name = speakerName {
            if speakerConfidence == "high" {
                speakerLabel = name
            } else if speakerConfidence == "conflict" {
                speakerLabel = name
            } else {
                speakerLabel = "\(name)?"
            }
        } else {
            speakerLabel = "???"
        }

        // Live output
        let learnIndicator = learned ? " 📚" : ""
        print("[\(speakerLabel)] (\(String(format: "%.1f", startTime))s-\(String(format: "%.1f", endTime))s) \(text)  [\(Int(processTime))ms]\(learnIndicator)")

        // Store segment
        segments.append([
            "start": startTime,
            "end": endTime,
            "text": text,
            "speaker": speakerName ?? "???",
            "score": speakerScore,
            "confidence": speakerConfidence
        ])
    }

    private func transcribeAudioSegment(audio: [Float], model: MLModel) -> String? {
        // Compute mel spectrogram
        let mel = computeMelSpectrogram(audio, filterbankPath: findFilterbank())

        // Apply LFR
        let lfr = applyLFR(mel)

        // Pad to fixed frames
        let padded = padToFixedFrames(lfr)

        // Run inference
        guard let logits = try? runInference(model: model, features: padded) else { return nil }

        // CTC decode
        let tokens = ctcGreedyDecode(logits)

        // Decode special tokens
        let (_, textTokens) = decodeSpecialTokens(tokens)

        // Decode to text
        if let tokenizer = tokenizer {
            let adjustedTokens = textTokens.map { $0 + 1 }
            return try? tokenizer.decode(adjustedTokens)
        }

        return nil
    }

    func startRecording() async throws {
        guard !isRunning else { return }

        // Reset state
        speechBuffer = []
        isSpeaking = false
        speechStartSample = 0
        totalSamples = 0
        silenceSamples = 0
        segments = []

        // Setup audio engine
        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else {
            throw NSError(domain: "LivePipeline", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio engine"])
        }

        let inputNode = engine.inputNode

        // Enable voice isolation if requested
        if useVoiceIsolation {
            do {
                try inputNode.setVoiceProcessingEnabled(true)
                print("🎤 Voice Isolation enabled")
            } catch {
                print("⚠️  Could not enable Voice Isolation: \(error)")
            }
        }

        // Get input format
        let inputFormat = inputNode.outputFormat(forBus: 0)
        print("📊 Input: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount) channels")

        // Create target format (16kHz mono)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: SAMPLE_RATE_DOUBLE,
            channels: 1,
            interleaved: false
        ) else {
            throw NSError(domain: "LivePipeline", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create target format"])
        }

        // Create converter
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw NSError(domain: "LivePipeline", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create converter"])
        }
        audioConverter = converter

        // Install tap on input node
        inputNode.installTap(onBus: 0, bufferSize: AVAudioFrameCount(CHUNK_SIZE * 4), format: inputFormat) { [weak self] buffer, _ in
            self?.handleAudioBuffer(buffer, converter: converter, targetFormat: targetFormat)
        }

        // Start engine
        engine.prepare()
        try engine.start()

        isRunning = true
        print("\n🎤 Recording... (press Ctrl+C to stop)\n")
        print(String(repeating: "-", count: 60))
    }

    private func handleAudioBuffer(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter, targetFormat: AVAudioFormat) {
        // Calculate output frame count
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount) else {
            return
        }

        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        guard status != .error, error == nil else { return }

        // Get float samples
        guard let channelData = outputBuffer.floatChannelData else { return }
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: Int(outputBuffer.frameLength)))

        // Process through VAD
        processVADChunk(samples)
    }

    func stopRecording() {
        guard isRunning, let engine = audioEngine else { return }

        // Flush any remaining speech
        if !speechBuffer.isEmpty && isSpeaking {
            let startTime = Double(speechStartSample) / SAMPLE_RATE_DOUBLE
            let endTime = Double(speechStartSample + speechBuffer.count) / SAMPLE_RATE_DOUBLE
            processingQueue.sync {
                processSegment(audio: speechBuffer, startTime: startTime, endTime: endTime)
            }
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        isRunning = false
        audioEngine = nil

        print(String(repeating: "-", count: 60))
        print("\n⏹️  Stopped.")

        // Show summary
        showSummary()
    }

    private func showSummary() {
        guard !segments.isEmpty else {
            print("\n⚠️  No segments detected")
            return
        }

        print("\n" + String(repeating: "=", count: 60))
        print("SUMMARY")
        print(String(repeating: "=", count: 60))

        let totalAudio = segments.reduce(0.0) { $0 + (($1["end"] as? Double ?? 0) - ($1["start"] as? Double ?? 0)) }
        print("\nSegments: \(segments.count)")
        print("Total audio: \(String(format: "%.1f", totalAudio))s")

        // Show transcript
        print("\n" + String(repeating: "-", count: 60))
        print("TRANSCRIPT")
        print(String(repeating: "-", count: 60) + "\n")

        for s in segments {
            let speaker = s["speaker"] as? String ?? "???"
            let start = s["start"] as? Double ?? 0
            let end = s["end"] as? Double ?? 0
            let text = s["text"] as? String ?? ""
            print("[\(speaker)] (\(String(format: "%.1f", start))s-\(String(format: "%.1f", end))s) \(text)")
        }
    }

    func run() async {
        print(String(repeating: "=", count: 60))
        print("SWIFT LIVE VOICE PIPELINE (VAD Streaming)")
        print(String(repeating: "=", count: 60))
        print("\n📢 Live output appears as you speak!")
        print("• Press Ctrl+C to stop\n")

        loadModels()

        do {
            try await startRecording()

            // Set up signal handler for graceful shutdown (retain in property)
            signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
            signal(SIGINT, SIG_IGN)

            signalSource?.setEventHandler { [weak self] in
                self?.stopRecording()
                self?.stopSemaphore.signal()
            }
            signalSource?.resume()

            // Wait on semaphore in background to avoid blocking async context
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DispatchQueue.global().async { [weak self] in
                    self?.stopSemaphore.wait()
                    continuation.resume()
                }
            }

        } catch {
            print("❌ Error: \(error)")
        }
    }
}

// MARK: - Vector Operations

func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
    guard a.count == b.count, !a.isEmpty else { return 0 }
    var dotProduct: Float = 0
    var normA: Float = 0
    var normB: Float = 0
    for i in 0..<a.count {
        dotProduct += a[i] * b[i]
        normA += a[i] * a[i]
        normB += b[i] * b[i]
    }
    let denom = sqrt(normA) * sqrt(normB)
    return denom > 0 ? dotProduct / denom : 0
}

func cosineDistance(_ a: [Float], _ b: [Float]) -> Float {
    return 1.0 - cosineSimilarity(a, b)
}

// MARK: - Speaker Embedding Extraction

func extractSpeakerEmbedding(audio: [Float], model: MLModel) -> [Float]? {
    // Prepare audio: pad or trim to XVECTOR_SAMPLES (48000 = 3 seconds)
    var processedAudio: [Float]
    if audio.count >= XVECTOR_SAMPLES {
        // Take middle portion for better quality
        let start = (audio.count - XVECTOR_SAMPLES) / 2
        processedAudio = Array(audio[start..<(start + XVECTOR_SAMPLES)])
    } else {
        // Pad with zeros
        processedAudio = audio + [Float](repeating: 0, count: XVECTOR_SAMPLES - audio.count)
    }

    // Debug: print audio stats
    print("  Speaker audio: first5=\(processedAudio.prefix(5).map { String(format: "%.6f", $0) })")

    do {
        // Create input array [1, 48000] - xvector uses FLOAT16 input
        let inputArray = try MLMultiArray(shape: [1, NSNumber(value: XVECTOR_SAMPLES)], dataType: .float16)

        // Convert Float32 audio to Float16 for xvector input using data pointer
        let inputPointer = inputArray.dataPointer.bindMemory(to: Float16.self, capacity: XVECTOR_SAMPLES)
        for i in 0..<XVECTOR_SAMPLES {
            inputPointer[i] = Float16(processedAudio[i])
        }

        // Run inference
        let input = try MLDictionaryFeatureProvider(dictionary: ["audio": inputArray])
        let output = try model.prediction(from: input)

        // Extract embedding [1, 1, 512] - xvector produces 512-dim embeddings
        guard let embeddingArray = output.featureValue(for: "embedding")?.multiArrayValue else {
            print("No embedding output")
            return nil
        }

        // Debug: print embedding array shape
        print("  Embedding shape: \(embeddingArray.shape)")

        // Convert to [Float] - xvector output is FLOAT16, shape [1, 1, 512]
        let embeddingDim = 512
        var embedding = [Float](repeating: 0, count: embeddingDim)
        let pointer = embeddingArray.dataPointer.bindMemory(to: Float16.self, capacity: embeddingArray.count)
        for i in 0..<embeddingDim {
            embedding[i] = Float(pointer[i])
        }

        return embedding
    } catch {
        print("Speaker embedding error: \(error)")
        return nil
    }
}

func findSpeakerModel() -> URL? {
    let path = "\(YOUPU_ROOT)/Sources/YouPu/Models/xvector.mlmodelc"
    let url = URL(fileURLWithPath: path)
    if FileManager.default.fileExists(atPath: url.path) {
        return url
    }
    return nil
}

func findVoiceLibrary() -> String? {
    let path = "\(YOUPU_ROOT)/Resources/voice_library_xvector.json"
    if FileManager.default.fileExists(atPath: path) {
        return path
    }
    return nil
}

// MARK: - Test with Python Features

func testWithPythonFeatures(_ path: String) async {
    guard let data = FileManager.default.contents(atPath: path) else {
        print("Failed to load Python features")
        return
    }

    let expectedSize = 500 * 560 * MemoryLayout<Float>.size
    guard data.count == expectedSize else {
        print("Python features size mismatch: expected \(expectedSize), got \(data.count)")
        return
    }

    // Load features
    let floats = data.withUnsafeBytes { buffer -> [Float] in
        let floatBuffer = buffer.bindMemory(to: Float.self)
        return Array(floatBuffer)
    }

    // Reshape to [[Float]]
    var features = [[Float]](repeating: [Float](repeating: 0, count: 560), count: 500)
    for i in 0..<500 {
        for j in 0..<560 {
            features[i][j] = floats[i * 560 + j]
        }
    }

    print("✅ Loaded Python features: (500, 560)")
    let allValues = floats
    print("📊 Stats: min=\(String(format: "%.3f", allValues.min()!)), max=\(String(format: "%.3f", allValues.max()!)), mean=\(String(format: "%.3f", allValues.reduce(0, +) / Float(allValues.count)))")

    // Load and run model
    guard let modelURL = findModel(named: "sensevoice-500-itn", ext: "mlmodelc") else {
        print("❌ Model not found")
        return
    }
    print("📦 Model path: \(modelURL.path)")

    do {
        let config = MLModelConfiguration()
        config.computeUnits = .all
        let model = try MLModel(contentsOf: modelURL, configuration: config)

        let logits = try runInference(model: model, features: features)
        print("✅ Inference complete, logits shape: (\(logits.count), \(logits.first?.count ?? 0))")

        // Debug: print raw logits for first few frames
        print("   Swift logits[0, :10]: \(logits[0].prefix(10).map { String(format: "%.4f", $0) })")
        print("   Swift logits[1, :10]: \(logits[1].prefix(10).map { String(format: "%.4f", $0) })")
        for i in 0..<10 {
            let maxIdx = logits[i].enumerated().max(by: { $0.element < $1.element })!.offset
            let maxVal = logits[i].max()!
            print("   Frame \(i): argmax=\(maxIdx), max_val=\(String(format: "%.4f", maxVal))")
        }

        let tokens = ctcGreedyDecode(logits)
        print("✅ Tokens with Python features: \(tokens.prefix(50))...")
        print("   Total tokens: \(tokens.count)")

    } catch {
        print("❌ Error: \(error)")
    }
}

// MARK: - Special Token Decoding

let LANG_TOKENS: [Int: String] = [
    24884: "auto",
    24885: "zh",
    24886: "en",
    24887: "yue",
    24888: "ja",
    24889: "ko",
]

let TASK_TOKENS: [Int: String] = [
    25004: "transcribe",
    25005: "translate",
]

let EMOTION_TOKENS: [Int: String] = [
    24993: "NEUTRAL",
    24994: "HAPPY",
    24995: "SAD",
    24996: "ANGRY",
]

let EVENT_TOKENS: [Int: String] = [
    25016: "Speech",
    25017: "Applause",
    25018: "BGM",
    25019: "Laughter",
]

struct TranscriptionResult {
    var language: String?
    var task: String?
    var emotion: String?
    var event: String?
    var tokens: [Int]
    var textTokens: [Int]
    var transcription: String?
    var speakerName: String?
    var speakerScore: Float
    var speakerConfidence: String
    var embedding: [Float]?
    var timeMs: Double
}

func decodeSpecialTokens(_ tokens: [Int]) -> (info: [String: String], textTokens: [Int]) {
    var info: [String: String] = [:]
    var textTokens: [Int] = []

    for tok in tokens {
        if let lang = LANG_TOKENS[tok] {
            info["language"] = lang
        } else if let task = TASK_TOKENS[tok] {
            info["task"] = task
        } else if let emotion = EMOTION_TOKENS[tok] {
            info["emotion"] = emotion
        } else if let event = EVENT_TOKENS[tok] {
            info["event"] = event
        } else {
            textTokens.append(tok)
        }
    }

    return (info, textTokens)
}

// MARK: - Transcribe Single Audio

func transcribeAudio(path: String, model: MLModel, filterbankPath: String?, tokenizer: SentencepieceTokenizer?, speakerModel: MLModel?, voiceLibrary: VoiceLibrary?) -> TranscriptionResult? {
    let fileName = (path as NSString).lastPathComponent
    print("\n" + String(repeating: "=", count: 60))
    print("Transcribing: \(fileName)")
    print(String(repeating: "=", count: 60))

    let startTotal = CFAbsoluteTimeGetCurrent()

    // Load audio
    guard let audio = loadAudio(from: path) else {
        print("Failed to load audio")
        return nil
    }
    let duration = Double(audio.count) / Double(SAMPLE_RATE)
    print("Audio duration: \(String(format: "%.2f", duration))s")

    // Mel spectrogram
    let mel = computeMelSpectrogram(audio, filterbankPath: filterbankPath)

    // LFR
    let lfr = applyLFR(mel)

    // Pad
    let padded = padToFixedFrames(lfr)

    // Inference
    do {
        let logits = try runInference(model: model, features: padded)

        // CTC decode
        let tokens = ctcGreedyDecode(logits)

        // Decode special tokens
        let (info, textTokens) = decodeSpecialTokens(tokens)

        // Decode tokens to text using SentencePiece
        // Note: Swift SentencePiece has off-by-one from Python/CoreML tokens
        // Need to add 1 to CoreML tokens before decoding with Swift SentencePiece
        var transcription: String? = nil
        if let tokenizer = tokenizer {
            let adjustedTokens = textTokens.map { $0 + 1 }
            transcription = try? tokenizer.decode(adjustedTokens)
        }

        // Speaker identification
        var speakerName: String? = nil
        var speakerScore: Float = 0
        var speakerConfidence = "low"
        var embedding: [Float]? = nil

        if let spkModel = speakerModel, let library = voiceLibrary {
            // Extract speaker embedding
            embedding = extractSpeakerEmbedding(audio: audio, model: spkModel)

            if let emb = embedding {
                let embNorm = sqrt(emb.map { $0 * $0 }.reduce(0, +))
                print("  Speaker embedding: norm=\(String(format: "%.2f", embNorm)), first5=\(emb.prefix(5).map { String(format: "%.2f", $0) })")
                // Match against voice library
                let (name, score, confidence) = library.match(emb)
                speakerName = name
                speakerScore = score
                speakerConfidence = confidence

                // Auto-learn from medium-confidence matches (expands boundary)
                if let matchedName = name, confidence == "medium", !matchedName.hasPrefix("[") {
                    let learned = library.autoLearn(matchedName, emb, score: score)
                    if learned {
                        print("  📚 Auto-learned embedding for \(matchedName)")
                    }
                }
            }
        }

        let totalTime = (CFAbsoluteTimeGetCurrent() - startTotal) * 1000

        // Format speaker label
        let speakerLabel: String
        if let name = speakerName {
            if speakerConfidence == "high" {
                speakerLabel = name
            } else if speakerConfidence == "conflict" {
                speakerLabel = name  // Already formatted as [A/B?]
            } else {
                speakerLabel = "\(name)?"
            }
        } else {
            speakerLabel = "???"
        }

        print("\nResults:")
        print("  Speaker: \(speakerLabel) (score: \(String(format: "%.2f", speakerScore)), \(speakerConfidence))")
        print("  Language: \(info["language"] ?? "unknown")")
        print("  Emotion: \(info["emotion"] ?? "unknown")")
        print("  Event: \(info["event"] ?? "unknown")")
        print("  Token count: \(tokens.count) (text tokens: \(textTokens.count))")
        print("  Processing time: \(String(format: "%.0f", totalTime))ms")

        if let text = transcription {
            print("\n  [\(speakerLabel)] \(text)")
        } else {
            print("\n  Token IDs: \(textTokens.prefix(30))...")
        }

        return TranscriptionResult(
            language: info["language"],
            task: info["task"],
            emotion: info["emotion"],
            event: info["event"],
            tokens: tokens,
            textTokens: textTokens,
            transcription: transcription,
            speakerName: speakerName,
            speakerScore: speakerScore,
            speakerConfidence: speakerConfidence,
            embedding: embedding,
            timeMs: totalTime
        )
    } catch {
        print("Inference error: \(error)")
        return nil
    }
}

// MARK: - Main

func main() async {
    print("=== Swift Voice Pipeline Transcription ===\n")

    // Audio files to transcribe (in YouPu project folder)
    let audioFiles = [
        "\(YOUPU_ROOT)/Resources/recordings/sample.wav",
        "\(YOUPU_ROOT)/Resources/recordings/test_recording.wav",
    ]

    // Load model
    guard let modelURL = findModel(named: "sensevoice-500-itn", ext: "mlmodelc") else {
        print("Model not found")
        return
    }
    print("Loading model: \(modelURL.lastPathComponent)")

    let config = MLModelConfiguration()
    config.computeUnits = .all

    guard let model = try? MLModel(contentsOf: modelURL, configuration: config) else {
        print("Failed to load model")
        return
    }
    print("Model loaded successfully")

    // Get filterbank path
    let filterbankPath = findFilterbank()

    // Load tokenizer for text decoding
    var tokenizer: SentencepieceTokenizer? = nil
    if let tokenizerPath = findTokenizerModel() {
        print("Loading tokenizer: \(tokenizerPath)")
        do {
            tokenizer = try SentencepieceTokenizer(modelPath: tokenizerPath)
            print("Tokenizer loaded successfully")

        } catch {
            print("Warning: Failed to load tokenizer: \(error)")
            print("Will output token IDs instead of text")
        }
    } else {
        print("Warning: Tokenizer model not found")
        print("Will output token IDs instead of text")
    }

    // Load speaker model
    var speakerModel: MLModel? = nil
    if let speakerModelURL = findSpeakerModel() {
        print("Loading speaker model: \(speakerModelURL.lastPathComponent)")
        let speakerConfig = MLModelConfiguration()
        speakerConfig.computeUnits = .all
        speakerModel = try? MLModel(contentsOf: speakerModelURL, configuration: speakerConfig)
        if speakerModel != nil {
            print("Speaker model loaded successfully")
        } else {
            print("Warning: Failed to load speaker model")
        }
    } else {
        print("Warning: Speaker model not found")
    }

    // Load voice library
    var voiceLibrary: VoiceLibrary? = nil
    if let libraryPath = findVoiceLibrary() {
        print("Loading voice library: \(libraryPath)")
        voiceLibrary = VoiceLibrary(path: libraryPath)
    } else {
        print("Warning: Voice library not found")
    }

    // Transcribe each file
    var results: [TranscriptionResult] = []

    for audioPath in audioFiles {
        if FileManager.default.fileExists(atPath: audioPath) {
            if let result = transcribeAudio(path: audioPath, model: model, filterbankPath: filterbankPath, tokenizer: tokenizer, speakerModel: speakerModel, voiceLibrary: voiceLibrary) {
                results.append(result)
            }
        } else {
            print("\nFile not found: \(audioPath)")
        }
    }

    // Summary
    print("\n" + String(repeating: "=", count: 60))
    print("SWIFT TRANSCRIPTION SUMMARY")
    print(String(repeating: "=", count: 60))

    for (i, r) in results.enumerated() {
        let fileName = (audioFiles[i] as NSString).lastPathComponent

        // Format speaker label
        let speakerLabel: String
        if let name = r.speakerName {
            if r.speakerConfidence == "high" {
                speakerLabel = name
            } else if r.speakerConfidence == "conflict" {
                speakerLabel = name
            } else {
                speakerLabel = "\(name)?"
            }
        } else {
            speakerLabel = "???"
        }

        print("\n\(fileName):")
        print("  Speaker: \(speakerLabel) (\(String(format: "%.2f", r.speakerScore)))")
        print("  Language: \(r.language ?? "unknown"), Emotion: \(r.emotion ?? "unknown")")
        print("  Tokens: \(r.tokens.count)")
        print("  Time: \(String(format: "%.0f", r.timeMs))ms")
        if let text = r.transcription {
            print("  [\(speakerLabel)] \(text)")
        }
    }
}

// MARK: - Audio Loading

func loadAudio(from path: String) -> [Float]? {
    let url = URL(fileURLWithPath: path)

    guard let file = try? AVAudioFile(forReading: url) else {
        print("   Cannot open audio file")
        return nil
    }

    let format = file.processingFormat
    let frameCount = AVAudioFrameCount(file.length)

    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
        return nil
    }

    try? file.read(into: buffer)

    guard let floatData = buffer.floatChannelData else {
        return nil
    }

    // Get mono channel
    var samples = Array(UnsafeBufferPointer(start: floatData[0], count: Int(buffer.frameLength)))

    // Resample to 16kHz if needed
    let sourceSampleRate = Int(format.sampleRate)
    if sourceSampleRate != SAMPLE_RATE {
        print("   Resampling from \(sourceSampleRate)Hz to \(SAMPLE_RATE)Hz")
        samples = resample(samples, from: sourceSampleRate, to: SAMPLE_RATE)
    }

    return samples
}

func resample(_ audio: [Float], from sourceSR: Int, to targetSR: Int) -> [Float] {
    let ratio = Double(targetSR) / Double(sourceSR)
    let outputLength = Int(Double(audio.count) * ratio)
    var output = [Float](repeating: 0, count: outputLength)

    // Simple linear interpolation resampling
    for i in 0..<outputLength {
        let srcIndex = Double(i) / ratio
        let srcIndexInt = Int(srcIndex)
        let frac = Float(srcIndex - Double(srcIndexInt))

        if srcIndexInt + 1 < audio.count {
            output[i] = audio[srcIndexInt] * (1 - frac) + audio[srcIndexInt + 1] * frac
        } else if srcIndexInt < audio.count {
            output[i] = audio[srcIndexInt]
        }
    }

    return output
}

// MARK: - KissFFT-based FFT (O(N log N) - replaces O(N²) manual DFT)

/// Global FFT configuration (reused for all frames)
private var kissFFTConfig: OpaquePointer?

/// Initialize KissFFT for real FFT of size N_FFT
func initializeKissFFT() {
    if kissFFTConfig == nil {
        kissFFTConfig = kiss_fftr_alloc(Int32(N_FFT), 0, nil, nil)
    }
}

/// Compute FFT magnitude using KissFFT
func computeFFTKiss(_ input: [Float]) -> [Float] {
    let N = input.count
    let numBins = N / 2 + 1

    // Initialize FFT config if needed
    if kissFFTConfig == nil {
        kissFFTConfig = kiss_fftr_alloc(Int32(N), 0, nil, nil)
    }

    guard let cfg = kissFFTConfig else {
        fatalError("Failed to allocate KissFFT configuration")
    }

    // Allocate output buffer for complex frequency bins
    let freqData = UnsafeMutablePointer<kiss_fft_cpx>.allocate(capacity: numBins)
    defer { freqData.deallocate() }

    // Perform FFT
    input.withUnsafeBufferPointer { inputPtr in
        kiss_fftr(cfg, inputPtr.baseAddress, freqData)
    }

    // Compute magnitude spectrum
    var magnitude = [Float](repeating: 0, count: numBins)
    for k in 0..<numBins {
        let real = freqData[k].r
        let imag = freqData[k].i
        magnitude[k] = sqrt(real * real + imag * imag)
    }

    return magnitude
}

// MARK: - Mel Spectrogram (using standard DFT)

func computeMelSpectrogram(_ audio: [Float], filterbankPath: String? = nil) -> [[Float]] {
    let frameLength = N_FFT
    let hopLength = HOP_LENGTH
    let halfN = frameLength / 2

    // Apply center padding (like torchaudio's center=True)
    // Pad n_fft/2 on each side using reflection
    let padLength = halfN
    var paddedAudio = [Float](repeating: 0, count: audio.count + 2 * padLength)

    // Reflect padding at start
    for i in 0..<padLength {
        paddedAudio[padLength - 1 - i] = audio[min(i + 1, audio.count - 1)]
    }
    // Copy original audio
    for i in 0..<audio.count {
        paddedAudio[padLength + i] = audio[i]
    }
    // Reflect padding at end
    for i in 0..<padLength {
        let srcIdx = audio.count - 2 - i
        paddedAudio[padLength + audio.count + i] = audio[max(0, srcIdx)]
    }

    let numFrames = max(1, (paddedAudio.count - frameLength) / hopLength + 1)

    // Load mel filterbank from file (torchaudio export) or create fallback
    let melFilterbank: [[Float]]
    if let path = filterbankPath, let loaded = loadMelFilterbank(path: path) {
        melFilterbank = loaded
        print("   Using torchaudio filterbank from file")
    } else {
        melFilterbank = createMelFilterbank(
            numMels: N_MELS,
            numFFT: frameLength,
            sampleRate: SAMPLE_RATE
        )
        print("   Using fallback filterbank (may differ from Python)")
    }

    // Precompute Hamming window
    var window = [Float](repeating: 0, count: frameLength)
    vDSP_hamm_window(&window, vDSP_Length(frameLength), 0)

    // Preallocate buffers
    var frame = [Float](repeating: 0, count: frameLength)
    var melEnergies = [Float](repeating: 0, count: N_MELS)

    var melFrames: [[Float]] = []
    melFrames.reserveCapacity(numFrames)

    // Debug: print first frame's FFT for comparison
    var debugPrinted = false

    for i in 0..<numFrames {
        let start = i * hopLength
        let end = min(start + frameLength, paddedAudio.count)
        let copyLength = end - start

        // Reset frame
        vDSP_vclr(&frame, 1, vDSP_Length(frameLength))

        // Copy audio samples from padded audio
        for j in 0..<copyLength {
            frame[j] = paddedAudio[start + j]
        }

        // Apply window: frame = frame * window
        vDSP_vmul(frame, 1, window, 1, &frame, 1, vDSP_Length(frameLength))

        // Debug first frame
        if i == 0 && !debugPrinted {
            print("   Debug: first windowed frame max=\(frame.max()!), first 5: \(frame[0..<5])")
        }

        // Compute FFT magnitude using KissFFT (O(N log N) instead of O(N²) DFT)
        let magnitude = computeFFTKiss(frame)

        // Debug first frame's magnitude
        if i == 0 && !debugPrinted {
            print("   Debug: magnitude first 5 bins: \(magnitude[0..<5])")
            debugPrinted = true
        }

        // Apply mel filterbank to magnitude spectrum
        for m in 0..<N_MELS {
            var sum: Float = 0
            vDSP_dotpr(magnitude, 1, melFilterbank[m], 1, &sum, vDSP_Length(magnitude.count))
            melEnergies[m] = sum
        }

        // Log scale: log(max(x, 1e-10))
        for m in 0..<N_MELS {
            melEnergies[m] = log(max(melEnergies[m], 1e-10))
        }

        melFrames.append(melEnergies)
    }

    return melFrames
}

func computeFFT(_ frame: [Float], setup: FFTSetup, log2n: vDSP_Length) -> [Float] {
    let n = frame.count
    let halfN = n / 2

    var realp = [Float](repeating: 0, count: halfN)
    var imagp = [Float](repeating: 0, count: halfN)

    // Pack input into split complex format
    frame.withUnsafeBufferPointer { framePtr in
        realp.withUnsafeMutableBufferPointer { realPtr in
            imagp.withUnsafeMutableBufferPointer { imagPtr in
                var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                framePtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfN) { complexPtr in
                    vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(halfN))
                }

                // FFT
                vDSP_fft_zrip(setup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))

                // Scale
                var scale = Float(1.0 / Float(n))
                vDSP_vsmul(realPtr.baseAddress!, 1, &scale, realPtr.baseAddress!, 1, vDSP_Length(halfN))
                vDSP_vsmul(imagPtr.baseAddress!, 1, &scale, imagPtr.baseAddress!, 1, vDSP_Length(halfN))
            }
        }
    }

    // Compute magnitude
    var magnitude = [Float](repeating: 0, count: halfN + 1)

    // DC component
    magnitude[0] = abs(realp[0])

    // Nyquist component
    magnitude[halfN] = abs(imagp[0])

    // Other components
    for i in 1..<halfN {
        magnitude[i] = sqrt(realp[i] * realp[i] + imagp[i] * imagp[i])
    }

    return magnitude
}

/// Load mel filterbank from binary file (exported from torchaudio)
/// Shape: (201 bins, 80 mels) stored as row-major float32
func loadMelFilterbank(path: String) -> [[Float]]? {
    guard let data = FileManager.default.contents(atPath: path) else {
        print("Failed to load mel filterbank from \(path)")
        return nil
    }

    let numBins = 201  // n_fft/2 + 1
    let numMels = 80
    let expectedSize = numBins * numMels * MemoryLayout<Float>.size

    guard data.count == expectedSize else {
        print("Filterbank file size mismatch: expected \(expectedSize), got \(data.count)")
        return nil
    }

    // Load as flat array
    let floats = data.withUnsafeBytes { buffer -> [Float] in
        let floatBuffer = buffer.bindMemory(to: Float.self)
        return Array(floatBuffer)
    }

    // Reshape to [[Float]] - torchaudio saves as (bins, mels) row-major
    // We need filterbank[mel][bin] for dot product
    var filterbank = [[Float]](repeating: [Float](repeating: 0, count: numBins), count: numMels)
    for bin in 0..<numBins {
        for mel in 0..<numMels {
            filterbank[mel][bin] = floats[bin * numMels + mel]
        }
    }

    return filterbank
}

/// Fallback: Create mel filterbank from scratch (less accurate than torchaudio)
func createMelFilterbank(numMels: Int, numFFT: Int, sampleRate: Int) -> [[Float]] {
    let numBins = numFFT / 2 + 1
    let fMin: Float = 0
    let fMax = Float(sampleRate) / 2

    // Mel scale conversion (HTK formula)
    func hzToMel(_ hz: Float) -> Float {
        return 2595 * log10(1 + hz / 700)
    }

    func melToHz(_ mel: Float) -> Float {
        return 700 * (pow(10, mel / 2595) - 1)
    }

    let melMin = hzToMel(fMin)
    let melMax = hzToMel(fMax)

    // Create mel center frequencies
    var melPoints = [Float](repeating: 0, count: numMels + 2)
    for i in 0..<(numMels + 2) {
        melPoints[i] = melMin + Float(i) * (melMax - melMin) / Float(numMels + 1)
    }

    // Convert to Hz frequencies
    var hzPoints = [Float](repeating: 0, count: numMels + 2)
    for i in 0..<(numMels + 2) {
        hzPoints[i] = melToHz(melPoints[i])
    }

    // Create filterbank using linear interpolation
    var filterbank = [[Float]](repeating: [Float](repeating: 0, count: numBins), count: numMels)

    // Frequency for each FFT bin
    let fftFreqs = (0..<numBins).map { Float($0) * Float(sampleRate) / Float(numFFT) }

    for m in 0..<numMels {
        let fLow = hzPoints[m]
        let fCenter = hzPoints[m + 1]
        let fHigh = hzPoints[m + 2]

        for k in 0..<numBins {
            let freq = fftFreqs[k]

            if freq >= fLow && freq < fCenter && fCenter > fLow {
                // Rising edge
                filterbank[m][k] = (freq - fLow) / (fCenter - fLow)
            } else if freq >= fCenter && freq <= fHigh && fHigh > fCenter {
                // Falling edge
                filterbank[m][k] = (fHigh - freq) / (fHigh - fCenter)
            }
        }
    }

    return filterbank
}

// MARK: - LFR Transform

func applyLFR(_ mel: [[Float]]) -> [[Float]] {
    var lfrFrames: [[Float]] = []

    var i = 0
    while i + LFR_M <= mel.count {
        var stacked: [Float] = []
        for j in 0..<LFR_M {
            stacked.append(contentsOf: mel[i + j])
        }
        lfrFrames.append(stacked)
        i += LFR_N
    }

    // Handle edge case - pad if needed
    if lfrFrames.isEmpty && !mel.isEmpty {
        var padded = mel
        while padded.count < LFR_M {
            padded.append(mel.last!)
        }
        var stacked: [Float] = []
        for j in 0..<LFR_M {
            stacked.append(contentsOf: padded[j])
        }
        lfrFrames.append(stacked)
    }

    return lfrFrames
}

func padToFixedFrames(_ features: [[Float]]) -> [[Float]] {
    var result = features
    let featureDim = features.first?.count ?? 560

    if result.count < FIXED_FRAMES {
        let padding = [Float](repeating: 0, count: featureDim)
        while result.count < FIXED_FRAMES {
            result.append(padding)
        }
    } else if result.count > FIXED_FRAMES {
        result = Array(result.prefix(FIXED_FRAMES))
    }

    return result
}

// MARK: - CoreML Inference

func runInference(model: MLModel, features: [[Float]]) throws -> [[Float]] {
    let frames = features.count
    let featureDim = features.first?.count ?? 560

    // Create input array
    let inputArray = try MLMultiArray(shape: [1, NSNumber(value: frames), NSNumber(value: featureDim)], dataType: .float32)

    // Debug: print MLMultiArray strides
    print("   MLMultiArray shape: \(inputArray.shape), strides: \(inputArray.strides)")

    // Copy features using proper indexing for 3D array [batch, time, feature]
    for i in 0..<frames {
        for j in 0..<featureDim {
            // For shape [1, frames, featureDim], index = batch*stride0 + time*stride1 + feat*stride2
            let stride0 = inputArray.strides[0].intValue
            let stride1 = inputArray.strides[1].intValue
            let stride2 = inputArray.strides[2].intValue
            let index = 0 * stride0 + i * stride1 + j * stride2
            inputArray[index] = NSNumber(value: features[i][j])
        }
    }

    // Debug: print first few input values
    print("   Input[0,0,0:5]: \(inputArray[0]), \(inputArray[1]), \(inputArray[2]), \(inputArray[3]), \(inputArray[4])")

    // Run inference
    let input = try MLDictionaryFeatureProvider(dictionary: ["audio_features": inputArray])
    let output = try model.prediction(from: input)

    // Extract logits
    guard let logitsArray = output.featureValue(for: "logits")?.multiArrayValue else {
        throw NSError(domain: "PipelineTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "No logits output"])
    }

    // Convert to [[Float]]
    let shape = logitsArray.shape.map { $0.intValue }
    let strides = logitsArray.strides.map { $0.intValue }
    print("   Output shape: \(shape), strides: \(strides)")

    let time = shape[1]
    let vocab = shape[2]

    var logits: [[Float]] = []
    let pointer = logitsArray.dataPointer.bindMemory(to: Float.self, capacity: logitsArray.count)

    // Use proper strides for indexing
    let stride0 = strides[0]  // batch stride
    let stride1 = strides[1]  // time stride
    let stride2 = strides[2]  // vocab stride

    for t in 0..<time {
        var frame: [Float] = []
        for v in 0..<vocab {
            let index = 0 * stride0 + t * stride1 + v * stride2
            frame.append(pointer[index])
        }
        logits.append(frame)
    }

    return logits
}

// MARK: - CTC Decoding

func ctcGreedyDecode(_ logits: [[Float]]) -> [Int] {
    var tokens: [Int] = []
    var prevToken = -1

    for frame in logits {
        // Find argmax
        var maxIdx = 0
        var maxVal = frame[0]
        for (i, val) in frame.enumerated() {
            if val > maxVal {
                maxVal = val
                maxIdx = i
            }
        }

        // Skip blanks (0) and consecutive duplicates
        if maxIdx != 0 && maxIdx != prevToken {
            tokens.append(maxIdx)
        }
        prevToken = maxIdx
    }

    return tokens
}

// MARK: - File Finding

func findTestAudio() -> String? {
    let candidates = [
        "\(YOUPU_ROOT)/Resources/recordings/test_recording.wav",
        "\(YOUPU_ROOT)/Resources/recordings/baseline.wav"
    ]

    for candidate in candidates {
        if FileManager.default.fileExists(atPath: candidate) {
            return candidate
        }
    }

    return nil
}

func findFilterbank() -> String? {
    let candidates = [
        "\(YOUPU_ROOT)/Resources/mel_filterbank.bin",
        "mel_filterbank.bin"  // Fallback: local project
    ]

    for candidate in candidates {
        if FileManager.default.fileExists(atPath: candidate) {
            return candidate
        }
    }

    return nil
}

func findModel(named name: String, ext: String) -> URL? {
    let path = "\(YOUPU_ROOT)/Sources/YouPu/Models/\(name).\(ext)"
    let url = URL(fileURLWithPath: path)
    if FileManager.default.fileExists(atPath: url.path) {
        return url
    }
    return nil
}

func findTokenizerModel() -> String? {
    let path = "\(YOUPU_ROOT)/Sources/YouPu/Models/chn_jpn_yue_eng_ko_spectok.bpe.model"
    if FileManager.default.fileExists(atPath: path) {
        return path
    }
    return nil
}

// MARK: - Command Line Interface

func printUsage() {
    print("""
    Swift Voice Pipeline

    USAGE:
      swift run                         # Process sample audio files
      swift run -- --live               # Live microphone transcription
      swift run -- --live --voice-isolation  # Live with noise reduction

    OPTIONS:
      --live              Enable live microphone mode
      --voice-isolation   Enable Apple Voice Isolation (macOS 26)
      --help              Show this help message
    """)
}

// Parse command line arguments
let args = CommandLine.arguments.dropFirst()

if args.contains("--help") || args.contains("-h") {
    printUsage()
} else if args.contains("--live") {
    // Live mode
    let useVoiceIsolation = args.contains("--voice-isolation")
    let pipeline = LivePipeline(voiceIsolation: useVoiceIsolation)
    await pipeline.run()
} else {
    // Default: process sample files
    await main()
}
