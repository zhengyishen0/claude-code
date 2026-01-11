#!/usr/bin/env swift
import Foundation
import CoreML
import Accelerate
import AVFoundation
import KissFFT

// MARK: - Configuration (matches Python exactly)

let SAMPLE_RATE: Int = 16000
let N_MELS: Int = 80
let N_FFT: Int = 400      // 25ms at 16kHz
let HOP_LENGTH: Int = 160 // 10ms at 16kHz
let LFR_M: Int = 7        // Stack 7 frames
let LFR_N: Int = 6        // Skip 6 frames
let FIXED_FRAMES: Int = 500

// Note: Python uses torchaudio.transforms.MelSpectrogram with power=1.0 (magnitude, not power)
// and NO CMVN normalization. Just: mel -> log -> LFR -> model

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

func transcribeAudio(path: String, model: MLModel, filterbankPath: String?) -> TranscriptionResult? {
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

        let totalTime = (CFAbsoluteTimeGetCurrent() - startTotal) * 1000

        // Decode special tokens
        let (info, textTokens) = decodeSpecialTokens(tokens)

        print("\nResults:")
        print("  Language: \(info["language"] ?? "unknown")")
        print("  Task: \(info["task"] ?? "unknown")")
        print("  Emotion: \(info["emotion"] ?? "unknown")")
        print("  Event: \(info["event"] ?? "unknown")")
        print("  Token count: \(tokens.count) (text tokens: \(textTokens.count))")
        print("  Processing time: \(String(format: "%.0f", totalTime))ms")
        print("\n  Token IDs: \(textTokens.prefix(30))...")

        return TranscriptionResult(
            language: info["language"],
            task: info["task"],
            emotion: info["emotion"],
            event: info["event"],
            tokens: tokens,
            textTokens: textTokens,
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

    // Audio files to transcribe (from main branch)
    let audioFiles = [
        "/Users/zhengyishen/Codes/claude-code/voice/recordings/sample.wav",
        "/Users/zhengyishen/Codes/claude-code/voice/recordings/test_recording.wav",
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

    // Transcribe each file
    var results: [TranscriptionResult] = []

    for audioPath in audioFiles {
        if FileManager.default.fileExists(atPath: audioPath) {
            if let result = transcribeAudio(path: audioPath, model: model, filterbankPath: filterbankPath) {
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
        print("\n\(fileName):")
        print("  Language: \(r.language ?? "unknown"), Emotion: \(r.emotion ?? "unknown")")
        print("  Tokens: \(r.tokens.count)")
        print("  Time: \(String(format: "%.0f", r.timeMs))ms")
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
        "test_recording.wav",
        "../test_recording.wav",
        "recordings/baseline.wav",
        "../recordings/baseline.wav"
    ]

    let cwd = FileManager.default.currentDirectoryPath

    for candidate in candidates {
        let path = (cwd as NSString).appendingPathComponent(candidate)
        if FileManager.default.fileExists(atPath: path) {
            return path
        }
    }

    // Try absolute path
    let absolutePath = "/Users/zhengyishen/Codes/claude-code-voice-isolation/voice/test_recording.wav"
    if FileManager.default.fileExists(atPath: absolutePath) {
        return absolutePath
    }

    return nil
}

func findFilterbank() -> String? {
    // Try relative paths from where the script is run
    let candidates = [
        "mel_filterbank.bin",           // If run from project root
        "../mel_filterbank.bin"         // If run from Sources/ directory
    ]

    for candidate in candidates {
        if FileManager.default.fileExists(atPath: candidate) {
            return candidate
        }
    }

    return nil
}

func findModel(named name: String, ext: String) -> URL? {
    let candidates = [
        // YouPu app models
        "../YouPu/Sources/YouPu/Models/\(name).\(ext)",
        // Main project models
        "/Users/zhengyishen/Codes/claude-code/voice/transcription/models/\(name).\(ext)",
        "/Users/zhengyishen/Codes/claude-code-voice-isolation/voice/YouPu/Sources/YouPu/Models/\(name).\(ext)"
    ]

    for candidate in candidates {
        let url = URL(fileURLWithPath: candidate)
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }
    }

    return nil
}

// Run
await main()
