import AVFoundation
import Accelerate

/// Audio capture with Voice Isolation support.
///
/// Based on the prototype in swift-isolation/, this class handles:
/// - Real-time microphone capture using AVAudioEngine
/// - Optional Voice Isolation (Apple's voice processing)
/// - VAD-based segmentation (voice activity detection)
/// - Resampling to 16kHz mono for ML models
class AudioCapture {
    private var engine: AVAudioEngine?
    private var isRunning = false

    // Audio format for ML models
    static let targetSampleRate: Double = 16000
    static let targetChannels: AVAudioChannelCount = 1

    // VAD settings
    private var vadThreshold: Float = 0.02  // RMS threshold for speech
    private var minSpeechDuration: TimeInterval = 0.3  // Min duration to trigger
    private var maxSilenceDuration: TimeInterval = 0.8  // Max silence before segment ends

    // Segment buffer
    private var segmentBuffer: [Float] = []
    private var isSpeaking = false
    private var silenceStart: Date?
    private var speechStart: Date?

    // Callback for completed segments
    private var onSegment: ((AudioSegment) -> Void)?

    // MARK: - Public API

    /// Start audio capture with optional Voice Isolation.
    ///
    /// - Parameters:
    ///   - voiceIsolation: Enable Apple's Voice Isolation (reduces background noise)
    ///   - onSegment: Callback for each detected speech segment
    func start(voiceIsolation: Bool, onSegment: @escaping (AudioSegment) -> Void) async throws {
        guard !isRunning else { return }

        self.onSegment = onSegment

        // Request microphone permission
        let granted = await requestMicrophonePermission()
        guard granted else {
            throw AudioCaptureError.permissionDenied
        }

        // Setup audio engine
        engine = AVAudioEngine()
        guard let engine = engine else {
            throw AudioCaptureError.engineCreationFailed
        }

        let inputNode = engine.inputNode

        // Enable Voice Isolation if requested
        if voiceIsolation {
            do {
                try inputNode.setVoiceProcessingEnabled(true)
                print("Voice Isolation enabled (9-channel input)")
            } catch {
                print("Warning: Could not enable Voice Isolation: \(error)")
            }
        }

        // Get input format (will be 9 channels with Voice Isolation, 1 channel without)
        let inputFormat = inputNode.outputFormat(forBus: 0)
        print("Input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount) channels")

        // Create converter to 16kHz mono
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.targetSampleRate,
            channels: Self.targetChannels,
            interleaved: false
        ) else {
            throw AudioCaptureError.formatCreationFailed
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioCaptureError.converterCreationFailed
        }

        // Install tap on input node
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, time in
            self?.processBuffer(buffer, converter: converter, targetFormat: targetFormat)
        }

        // Start engine
        engine.prepare()
        try engine.start()

        isRunning = true
        print("Audio capture started")
    }

    /// Stop audio capture.
    func stop() {
        guard isRunning, let engine = engine else { return }

        // Flush any remaining audio
        if !segmentBuffer.isEmpty && isSpeaking {
            finalizeSegment()
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        isRunning = false
        self.engine = nil

        print("Audio capture stopped")
    }

    // MARK: - Audio Processing

    private func processBuffer(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter, targetFormat: AVAudioFormat) {
        // Convert to 16kHz mono
        guard let convertedBuffer = convertBuffer(buffer, converter: converter, targetFormat: targetFormat) else {
            return
        }

        // Get float samples
        guard let channelData = convertedBuffer.floatChannelData else { return }
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: Int(convertedBuffer.frameLength)))

        // Calculate RMS for VAD
        let rms = calculateRMS(samples)

        // Simple VAD logic
        processVAD(samples: samples, rms: rms)
    }

    private func convertBuffer(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter, targetFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        // Calculate output frame count
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount) else {
            return nil
        }

        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        guard status != .error, error == nil else {
            print("Conversion error: \(error?.localizedDescription ?? "unknown")")
            return nil
        }

        return outputBuffer
    }

    // MARK: - Voice Activity Detection (Simple)

    private func processVAD(samples: [Float], rms: Float) {
        let now = Date()

        if rms > vadThreshold {
            // Speech detected
            if !isSpeaking {
                // Start of speech
                isSpeaking = true
                speechStart = now
                silenceStart = nil
            }

            // Add samples to segment buffer
            segmentBuffer.append(contentsOf: samples)

        } else {
            // Silence detected
            if isSpeaking {
                if silenceStart == nil {
                    silenceStart = now
                }

                // Still add samples during silence gap
                segmentBuffer.append(contentsOf: samples)

                // Check if silence duration exceeded threshold
                if let silenceStart = silenceStart,
                   now.timeIntervalSince(silenceStart) > maxSilenceDuration {
                    // End of speech segment
                    finalizeSegment()
                }
            }
        }
    }

    private func finalizeSegment() {
        guard !segmentBuffer.isEmpty else { return }

        // Check minimum duration
        let duration = Double(segmentBuffer.count) / Self.targetSampleRate
        guard duration >= minSpeechDuration else {
            resetSegment()
            return
        }

        // Create audio data
        let audioData = segmentBuffer.withUnsafeBytes { Data($0) }

        // TODO: Extract speaker embedding here using x-vector model
        // For now, pass nil - will be added when CoreML model is integrated
        let embedding: [Float]? = nil

        let segment = AudioSegment(
            audioData: audioData,
            embedding: embedding,
            duration: duration
        )

        // Notify callback
        onSegment?(segment)

        resetSegment()
    }

    private func resetSegment() {
        segmentBuffer.removeAll()
        isSpeaking = false
        silenceStart = nil
        speechStart = nil
    }

    // MARK: - Utilities

    private func calculateRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }

        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
        return rms
    }

    private func requestMicrophonePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }
}

// MARK: - Errors

enum AudioCaptureError: Error, LocalizedError {
    case permissionDenied
    case engineCreationFailed
    case formatCreationFailed
    case converterCreationFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone permission denied"
        case .engineCreationFailed:
            return "Failed to create audio engine"
        case .formatCreationFailed:
            return "Failed to create audio format"
        case .converterCreationFailed:
            return "Failed to create audio converter"
        }
    }
}
