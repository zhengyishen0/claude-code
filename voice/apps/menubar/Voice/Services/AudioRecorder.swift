import AVFoundation
import Foundation

class AudioRecorder {
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var isRecording = false
    private var tempURL: URL?

    private let sampleRate: Double = 16000
    private let channels: AVAudioChannelCount = 1

    func startRecording() {
        guard !isRecording else { return }

        do {
            let engine = AVAudioEngine()
            let inputNode = engine.inputNode

            // Create temp file for recording
            let tempDir = FileManager.default.temporaryDirectory
            let fileName = "voice_\(Date().timeIntervalSince1970).wav"
            tempURL = tempDir.appendingPathComponent(fileName)

            // Get input format and create output format (16kHz mono)
            let inputFormat = inputNode.outputFormat(forBus: 0)
            let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: channels,
                interleaved: false
            )!

            // Create audio file
            audioFile = try AVAudioFile(
                forWriting: tempURL!,
                settings: outputFormat.settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )

            // Create converter for resampling
            guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
                print("Failed to create audio converter")
                return
            }

            // Install tap on input
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
                self?.processAudioBuffer(buffer, converter: converter, outputFormat: outputFormat)
            }

            try engine.start()
            audioEngine = engine
            isRecording = true

            print("Recording started...")
        } catch {
            print("Failed to start recording: \(error)")
        }
    }

    func stopRecording(completion: @escaping (URL?) -> Void) {
        guard isRecording else {
            completion(nil)
            return
        }

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioFile = nil
        isRecording = false

        print("Recording stopped")
        completion(tempURL)
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer,
                                     converter: AVAudioConverter,
                                     outputFormat: AVAudioFormat) {
        // Calculate output buffer size based on sample rate ratio
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: outputFrameCount
        ) else { return }

        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        guard status != .error, error == nil else {
            print("Conversion error: \(error?.localizedDescription ?? "unknown")")
            return
        }

        // Write to file
        do {
            try audioFile?.write(from: outputBuffer)
        } catch {
            print("Failed to write audio: \(error)")
        }
    }
}
