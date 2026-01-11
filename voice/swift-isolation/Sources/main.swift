import AVFoundation
import Foundation

/// Voice Isolation Live Capture Tool
/// Records audio with Apple's Voice Isolation enabled/disabled for comparison

class LiveRecorder {
    let engine = AVAudioEngine()
    var outputFile: AVAudioFile?
    var isRecording = false
    var recordedFrames: AVAudioFrameCount = 0

    /// Record audio from microphone with optional voice isolation
    func record(outputPath: String, duration: Double, voiceIsolation: Bool) async throws {
        let outputURL = URL(fileURLWithPath: outputPath)

        // Configure audio session for voice processing
        let inputNode = engine.inputNode

        // Enable/disable voice processing (includes voice isolation, echo cancellation, noise suppression)
        do {
            try inputNode.setVoiceProcessingEnabled(voiceIsolation)
            print("Voice Processing: \(voiceIsolation ? "ENABLED" : "DISABLED")")
        } catch {
            print("Voice Processing setup failed: \(error.localizedDescription)")
            if voiceIsolation {
                throw error
            }
        }

        // Get the native format of the input
        let inputFormat = inputNode.outputFormat(forBus: 0)
        print("Input Format: \(Int(inputFormat.sampleRate))Hz, \(inputFormat.channelCount) channel(s)")

        // Output format: mono 16kHz for Python pipeline compatibility
        guard let outputFormat = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1) else {
            throw NSError(domain: "VoiceIsolation", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create output format"])
        }

        outputFile = try AVAudioFile(forWriting: outputURL, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: outputFormat.sampleRate,
            AVNumberOfChannelsKey: outputFormat.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ])

        print("Output Format: \(Int(outputFormat.sampleRate))Hz, \(outputFormat.channelCount) channel(s)")

        var tapCallCount = 0

        // Install tap on input node to capture audio
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, time in
            guard let self = self, self.isRecording else { return }

            tapCallCount += 1
            if tapCallCount == 1 {
                print("  First buffer received: \(buffer.frameLength) frames")
            }

            // Get the actual buffer format
            let bufferFormat = buffer.format

            // Convert to mono 16kHz if needed
            if bufferFormat.sampleRate != 16000 || bufferFormat.channelCount != 1 {
                // Manual conversion: downsample and take first channel
                let inputSamples = buffer.frameLength
                let outputSamples = AVAudioFrameCount(Double(inputSamples) * 16000.0 / bufferFormat.sampleRate)

                guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputSamples) else {
                    print("  ERROR: Failed to create converted buffer")
                    return
                }
                convertedBuffer.frameLength = outputSamples

                guard let srcData = buffer.floatChannelData,
                      let dstData = convertedBuffer.floatChannelData else {
                    print("  ERROR: No float channel data")
                    return
                }

                // Simple linear interpolation for downsampling
                let ratio = bufferFormat.sampleRate / 16000.0
                for i in 0..<Int(outputSamples) {
                    let srcIdx = Double(i) * ratio
                    let srcIdxFloor = Int(srcIdx)
                    let srcIdxCeil = min(srcIdxFloor + 1, Int(inputSamples) - 1)
                    let frac = Float(srcIdx - Double(srcIdxFloor))

                    // Take first channel only (channel 0 contains the isolated voice)
                    let v1 = srcData[0][srcIdxFloor]
                    let v2 = srcData[0][srcIdxCeil]
                    dstData[0][i] = v1 * (1 - frac) + v2 * frac
                }

                do {
                    try self.outputFile?.write(from: convertedBuffer)
                    self.recordedFrames += convertedBuffer.frameLength
                } catch {
                    print("  Write error: \(error)")
                }
            } else {
                // Already in correct format
                do {
                    try self.outputFile?.write(from: buffer)
                    self.recordedFrames += buffer.frameLength
                } catch {
                    print("  Write error: \(error)")
                }
            }
        }

        // Start engine
        try engine.start()
        isRecording = true

        print("\nRecording for \(duration) seconds...")
        print("(Speak now)")

        // Record for specified duration
        try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))

        // Stop recording
        isRecording = false

        // Small delay to ensure last buffers are processed
        try await Task.sleep(nanoseconds: 100_000_000)  // 100ms

        inputNode.removeTap(onBus: 0)
        engine.stop()

        // Close file explicitly to flush all data
        outputFile = nil

        let recordedDuration = Double(recordedFrames) / 16000.0
        print("\nRecording complete!")
        print("Output: \(outputPath)")
        print("Duration: \(String(format: "%.2f", recordedDuration))s")
        print("Frames: \(recordedFrames) @ 16kHz mono")
    }
}

// MARK: - Main

func printUsage() {
    print("""
    Voice Isolation Capture Tool

    Records audio with Apple's Voice Isolation ON or OFF for comparison testing.

    USAGE:
        voice-isolate record <output.wav> <duration_sec> [--isolation]

    OPTIONS:
        --isolation    Enable Voice Isolation (default: off)

    EXAMPLES:
        # Record 10 seconds WITHOUT voice isolation (baseline)
        voice-isolate record baseline.wav 10

        # Record 10 seconds WITH voice isolation
        voice-isolate record isolated.wav 10 --isolation

    COMPARISON WORKFLOW:
        1. voice-isolate record baseline.wav 10
        2. voice-isolate record isolated.wav 10 --isolation
        3. Run both through your transcription pipeline
        4. Compare transcription accuracy and speaker ID consistency
    """)
}

// Parse arguments
let args = CommandLine.arguments

if args.count < 2 {
    printUsage()
    exit(0)
}

let command = args[1]

switch command {
case "record":
    guard args.count >= 4 else {
        print("Error: Missing arguments for record command")
        printUsage()
        exit(1)
    }

    let outputPath = args[2]
    guard let duration = Double(args[3]) else {
        print("Error: Invalid duration: \(args[3])")
        exit(1)
    }

    let useIsolation = args.contains("--isolation")

    print("Voice Isolation Capture")
    print("=======================")
    print("Output: \(outputPath)")
    print("Duration: \(duration)s")
    print("Mode: \(useIsolation ? "Voice Isolation ON" : "Standard (no isolation)")")
    print("")

    let recorder = LiveRecorder()
    let semaphore = DispatchSemaphore(value: 0)
    var exitCode: Int32 = 0

    Task {
        do {
            try await recorder.record(outputPath: outputPath, duration: duration, voiceIsolation: useIsolation)
        } catch {
            print("Error: \(error.localizedDescription)")
            exitCode = 1
        }
        semaphore.signal()
    }

    semaphore.wait()
    exit(exitCode)

default:
    printUsage()
    exit(0)
}
