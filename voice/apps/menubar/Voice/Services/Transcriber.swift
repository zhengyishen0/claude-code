import Foundation
import AVFoundation
import VoicePipeline

struct TranscriptionResult {
    let text: String?
    let modelTime: TimeInterval
}

class Transcriber {
    private let engine: ASREngine

    init(engine: ASREngine) {
        self.engine = engine
    }

    func transcribe(audioURL: URL, completion: @escaping (TranscriptionResult) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                completion(TranscriptionResult(text: nil, modelTime: 0))
                return
            }

            let result = self.runTranscription(audioURL: audioURL)
            completion(result)
        }
    }

    private func runTranscription(audioURL: URL) -> TranscriptionResult {
        // Load audio file to float array
        guard let audioSamples = loadAudioFile(url: audioURL) else {
            return TranscriptionResult(text: nil, modelTime: 0)
        }

        // Convert Swift [Float] to KotlinFloatArray
        let kotlinArray = KotlinFloatArray(size: Int32(audioSamples.count))
        for (index, sample) in audioSamples.enumerated() {
            kotlinArray.set(index: Int32(index), value: sample)
        }

        let modelStart = Date()

        // Call KMP ASREngine directly (no subprocess!)
        let text = engine.transcribe(audio: kotlinArray)

        let modelTime = Date().timeIntervalSince(modelStart)

        return TranscriptionResult(text: text, modelTime: modelTime)
    }

    /// Load WAV/M4A audio file and convert to 16kHz mono float samples
    private func loadAudioFile(url: URL) -> [Float]? {
        do {
            let audioFile = try AVAudioFile(forReading: url)

            // Target format: 16kHz, mono, float
            guard let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16000,
                channels: 1,
                interleaved: false
            ) else {
                print("Failed to create target audio format")
                return nil
            }

            // Create converter
            guard let converter = AVAudioConverter(from: audioFile.processingFormat, to: targetFormat) else {
                print("Failed to create audio converter")
                return nil
            }

            // Calculate output buffer size
            let inputLength = AVAudioFrameCount(audioFile.length)
            let ratio = targetFormat.sampleRate / audioFile.processingFormat.sampleRate
            let outputLength = AVAudioFrameCount(Double(inputLength) * ratio)

            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputLength) else {
                print("Failed to create output buffer")
                return nil
            }

            // Read input
            guard let inputBuffer = AVAudioPCMBuffer(
                pcmFormat: audioFile.processingFormat,
                frameCapacity: inputLength
            ) else {
                print("Failed to create input buffer")
                return nil
            }

            try audioFile.read(into: inputBuffer)

            // Convert
            var error: NSError?
            let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
                outStatus.pointee = .haveData
                return inputBuffer
            }

            converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

            if let error = error {
                print("Audio conversion error: \(error)")
                return nil
            }

            // Extract float samples
            guard let floatData = outputBuffer.floatChannelData?[0] else {
                print("Failed to get float channel data")
                return nil
            }

            let frameCount = Int(outputBuffer.frameLength)
            var samples = [Float](repeating: 0, count: frameCount)
            for i in 0..<frameCount {
                samples[i] = floatData[i]
            }

            return samples

        } catch {
            print("Error loading audio file: \(error)")
            return nil
        }
    }

    // Legacy methods for compatibility (no-op since model is fixed in ASREngine)
    func setModel(_ model: ASRModel) {
        // Model selection handled by ASREngine internally
        // For now, only SenseVoice is supported
    }
}
