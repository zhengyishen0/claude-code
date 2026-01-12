package com.voice.pipeline

// Default paths
private const val MODEL_DIR = "/Users/zhengyishen/Codes/claude-code/voice/YouPu/Sources/YouPu/Models"
private const val VAD_MODEL_PATH = "/Users/zhengyishen/Codes/claude-code/voice/swift-pipeline-test/Models/silero-vad-unified-256ms-v6.0.0.mlmodelc"
private const val ONNX_MODEL_DIR = "/Users/zhengyishen/Codes/claude-code/voice/claude-code-kmp-voice-pipeline/voice/kmp-pipeline/Models/onnx"
private const val VOICE_LIBRARY_PATH = "/Users/zhengyishen/Codes/claude-code/voice/YouPu/Resources/voice_library_xvector.json"

// Backend selection
enum class Backend { COREML, ONNX }

fun main(args: Array<String>) {
    val useOnnx = args.contains("--onnx")
    val backend = if (useOnnx) Backend.ONNX else Backend.COREML
    val filteredArgs = args.filter { it != "--onnx" }

    when {
        filteredArgs.isEmpty() -> showHelp()
        filteredArgs[0] == "test" -> runTests()
        filteredArgs[0] == "live" -> runLive(backend)
        filteredArgs[0] == "file" && filteredArgs.size > 1 -> runFile(filteredArgs[1], backend)
        filteredArgs[0] == "benchmark" && filteredArgs.size > 1 -> runBenchmark(filteredArgs[1])
        filteredArgs[0] == "benchmark" -> runBenchmark(null)
        else -> showHelp()
    }
}

private fun showHelp() {
    println("""
KMP Voice Pipeline - macOS
==========================

Usage:
  kmp-pipeline test                 Run all tests
  kmp-pipeline live [--onnx]        Start live transcription (press ESC to stop)
  kmp-pipeline file <path> [--onnx] Process audio file
  kmp-pipeline benchmark [path]     Compare CoreML vs ONNX performance

Options:
  --onnx    Use ONNX Runtime instead of CoreML (default: CoreML)

Examples:
  ./build/bin/macos/debugExecutable/kmp-pipeline.kexe live
  ./build/bin/macos/debugExecutable/kmp-pipeline.kexe live --onnx
  ./build/bin/macos/debugExecutable/kmp-pipeline.kexe file recording.wav --onnx
  ./build/bin/macos/debugExecutable/kmp-pipeline.kexe benchmark recording.wav
    """.trimIndent())
}

private fun runLive(backend: Backend) {
    println("KMP Voice Pipeline - Live Mode (${backend.name})")
    println("=" .repeat(40))

    // Load vocabulary
    val vocabPath = "$MODEL_DIR/vocab.json"
    if (!TokenDecoder.loadVocabulary(vocabPath)) {
        println("Warning: Could not load vocabulary from $vocabPath")
    }

    // Load mel filterbank
    val filterbankPath = "/Users/zhengyishen/Codes/claude-code/voice/YouPu/Resources/mel_filterbank.bin"
    AudioProcessing.loadMelFilterbank(filterbankPath)

    when (backend) {
        Backend.COREML -> runLiveWithCoreML()
        Backend.ONNX -> runLiveWithONNX()
    }
}

private fun runLiveWithCoreML() {
    // Load CoreML models
    print("Loading CoreML models... ")
    val startLoad = kotlin.system.getTimeMillis()

    val vadModel = CoreMLModel.load(VAD_MODEL_PATH)
    val asrModel = CoreMLModel.load("$MODEL_DIR/sensevoice-500-itn.mlmodelc")
    val speakerModel = CoreMLModel.load("$MODEL_DIR/xvector.mlmodelc")

    val loadTime = kotlin.system.getTimeMillis() - startLoad
    println("${loadTime}ms")

    if (vadModel == null || asrModel == null || speakerModel == null) {
        println("ERROR: Failed to load one or more CoreML models")
        return
    }

    // Run live transcription
    runLiveTranscription(vadModel, asrModel, speakerModel, VOICE_LIBRARY_PATH)
}

private fun runLiveWithONNX() {
    // Load ONNX models
    print("Loading ONNX models from $ONNX_MODEL_DIR... ")
    val startLoad = kotlin.system.getTimeMillis()

    val onnxManager = ONNXModelManager(ONNX_MODEL_DIR)
    if (!onnxManager.loadModels()) {
        println("ERROR: Failed to load ONNX models")
        return
    }

    val loadTime = kotlin.system.getTimeMillis() - startLoad
    println("${loadTime}ms")

    // Run live transcription with ONNX
    runLiveTranscriptionONNX(onnxManager, VOICE_LIBRARY_PATH)
}

private fun runFile(audioPath: String, backend: Backend) {
    println("KMP Voice Pipeline - File Mode (${backend.name})")
    println("=" .repeat(40))

    // Load vocabulary
    val vocabPath = "$MODEL_DIR/vocab.json"
    if (!TokenDecoder.loadVocabulary(vocabPath)) {
        println("Warning: Could not load vocabulary from $vocabPath")
    }

    // Load mel filterbank
    val filterbankPath = "/Users/zhengyishen/Codes/claude-code/voice/YouPu/Resources/mel_filterbank.bin"
    AudioProcessing.loadMelFilterbank(filterbankPath)

    when (backend) {
        Backend.COREML -> runFileWithCoreML(audioPath)
        Backend.ONNX -> runFileWithONNX(audioPath)
    }
}

private fun runFileWithCoreML(audioPath: String) {
    // Load CoreML models
    print("Loading CoreML models... ")
    val startLoad = kotlin.system.getTimeMillis()

    val vadModel = CoreMLModel.load(VAD_MODEL_PATH)
    val asrModel = CoreMLModel.load("$MODEL_DIR/sensevoice-500-itn.mlmodelc")
    val speakerModel = CoreMLModel.load("$MODEL_DIR/xvector.mlmodelc")

    val loadTime = kotlin.system.getTimeMillis() - startLoad
    println("${loadTime}ms")

    if (vadModel == null || asrModel == null || speakerModel == null) {
        println("ERROR: Failed to load one or more CoreML models")
        return
    }

    // Process file
    processFileTranscription(audioPath, vadModel, asrModel, speakerModel, VOICE_LIBRARY_PATH)
}

private fun runFileWithONNX(audioPath: String) {
    // Load ONNX models
    print("Loading ONNX models... ")
    val startLoad = kotlin.system.getTimeMillis()

    val onnxManager = ONNXModelManager(ONNX_MODEL_DIR)
    if (!onnxManager.loadModels()) {
        println("ERROR: Failed to load ONNX models")
        return
    }

    val loadTime = kotlin.system.getTimeMillis() - startLoad
    println("${loadTime}ms")

    // Process file with ONNX
    processFileTranscriptionONNX(audioPath, onnxManager, VOICE_LIBRARY_PATH)
}

/**
 * Benchmark comparing CoreML vs ONNX performance
 */
private fun runBenchmark(audioPath: String?) {
    println("KMP Voice Pipeline - Benchmark Mode")
    println("=" .repeat(40))

    // Load vocabulary
    val vocabPath = "$MODEL_DIR/vocab.json"
    if (!TokenDecoder.loadVocabulary(vocabPath)) {
        println("Warning: Could not load vocabulary from $vocabPath")
    }

    // Load mel filterbank
    val filterbankPath = "/Users/zhengyishen/Codes/claude-code/voice/YouPu/Resources/mel_filterbank.bin"
    AudioProcessing.loadMelFilterbank(filterbankPath)

    // Read test audio
    val testAudioPath = audioPath ?: "/Users/zhengyishen/Codes/claude-code/voice/recordings/recording_20260112_002226.wav"
    print("Reading audio file: $testAudioPath... ")
    val audio = AudioFileReader.readFile(testAudioPath)
    if (audio == null) {
        println("FAILED")
        return
    }
    println("${audio.size} samples (${audio.size.toFloat() / SAMPLE_RATE}s)")

    // Compute mel spectrogram once
    println("\nComputing mel spectrogram...")
    val mel = AudioProcessing.computeMelSpectrogram(audio)
    val lfr = LFRTransform.apply(mel)
    val padded = LFRTransform.padToFixedFrames(lfr)
    println("LFR features: ${padded.size} frames x ${padded[0].size} features")

    // Prepare xvector input (3 seconds)
    val xvectorSamples = minOf(audio.size, XVECTOR_SAMPLES)
    val xvectorInput = audio.copyOfRange(0, xvectorSamples)

    println("\n" + "=" .repeat(60))
    println("BENCHMARK RESULTS")
    println("=" .repeat(60))

    // Benchmark CoreML
    println("\n[CoreML Backend]")
    benchmarkCoreML(audio, padded, xvectorInput)

    // Benchmark ONNX
    println("\n[ONNX Runtime Backend]")
    benchmarkONNX(audio, padded, xvectorInput)

    println("\n" + "=" .repeat(60))
}

private fun runTests() {
    println("KMP Voice Pipeline - Test Mode")
    println("==============================")

    // Test pure Kotlin components
    testVectorOps()
    testSpeakerProfile()
    testLFRTransform()
    testCTCDecoder()

    println()
    println("All pure Kotlin tests passed!")

    // Test CoreML model loading
    testCoreMLModels()

    // Test audio processing
    testAudioProcessing()

    // End-to-end pipeline test
    testFullPipeline()
}

private fun testCoreMLModels() {
    println("\n[Testing CoreML Model Loading]")

    val modelDir = "/Users/zhengyishen/Codes/claude-code/voice/YouPu/Sources/YouPu/Models"

    // Test ASR model
    val asrPath = "$modelDir/sensevoice-500-itn.mlmodelc"
    print("  ASR model: ")
    val asrModel = CoreMLModel.load(asrPath)
    if (asrModel != null) {
        println("OK")
    } else {
        println("FAILED")
    }

    // Test speaker model
    val speakerPath = "$modelDir/xvector.mlmodelc"
    print("  Speaker model: ")
    val speakerModel = CoreMLModel.load(speakerPath)
    if (speakerModel != null) {
        println("OK")
    } else {
        println("FAILED")
    }

    // Test VAD model (in swift-pipeline-test)
    val vadPath = "/Users/zhengyishen/Codes/claude-code/voice/swift-pipeline-test/Models/silero-vad-unified-256ms-v6.0.0.mlmodelc"
    print("  VAD model: ")
    val vadModel = CoreMLModel.load(vadPath)
    if (vadModel != null) {
        println("OK")
    } else {
        println("FAILED (check path)")
    }

    println("  CoreML loading: ${if (asrModel != null && speakerModel != null) "OK" else "PARTIAL"}")
}

private fun testAudioProcessing() {
    println("\n[Testing Audio Processing]")

    // Load mel filterbank from file
    val filterbankPath = "/Users/zhengyishen/Codes/claude-code/voice/YouPu/Resources/mel_filterbank.bin"
    val loaded = AudioProcessing.loadMelFilterbank(filterbankPath)
    println("  Mel filterbank: ${if (loaded) "loaded from file" else "generated (file not found)"}")

    // Create test audio (1 second of 440Hz sine wave)
    val duration = 1.0f
    val frequency = 440f
    val numSamples = (duration * SAMPLE_RATE).toInt()
    val testAudio = FloatArray(numSamples) { i ->
        kotlin.math.sin(2.0 * kotlin.math.PI * frequency * i / SAMPLE_RATE).toFloat() * 0.5f
    }
    println("  Test audio: ${numSamples} samples (${duration}s at ${SAMPLE_RATE}Hz)")

    // Compute mel spectrogram
    val startTime = kotlin.system.getTimeMillis()
    val mel = AudioProcessing.computeMelSpectrogram(testAudio)
    val elapsed = kotlin.system.getTimeMillis() - startTime
    println("  Mel spectrogram: ${mel.size} frames x ${mel.firstOrNull()?.size ?: 0} mels (${elapsed}ms)")

    // Apply LFR
    val lfr = LFRTransform.apply(mel)
    println("  LFR transform: ${lfr.size} frames x ${lfr.firstOrNull()?.size ?: 0} features")

    // Pad to fixed frames
    val padded = LFRTransform.padToFixedFrames(lfr)
    println("  Padded: ${padded.size} frames (fixed)")

    // Test RMS
    val rms = AudioProcessing.computeRMS(testAudio)
    println("  RMS: $rms (expected ~0.35 for 0.5 amplitude sine)")

    println("  AudioProcessing: OK")
}

private fun testFullPipeline() {
    println("\n[Testing Full Pipeline - End-to-End]")

    val modelDir = "/Users/zhengyishen/Codes/claude-code/voice/YouPu/Sources/YouPu/Models"
    val vadModelPath = "/Users/zhengyishen/Codes/claude-code/voice/swift-pipeline-test/Models/silero-vad-unified-256ms-v6.0.0.mlmodelc"
    val testAudioPath = "/Users/zhengyishen/Codes/claude-code/voice/recordings/recording_20260112_002226.wav"

    // Load vocabulary for text decoding
    print("  Loading vocabulary... ")
    val vocabPath = "$modelDir/vocab.json"
    if (TokenDecoder.loadVocabulary(vocabPath)) {
        println("OK (${TokenDecoder.vocabularySize()} tokens)")
    } else {
        println("FAILED - will show token IDs only")
    }

    // Load models
    print("  Loading models... ")
    val startLoad = kotlin.system.getTimeMillis()

    val vadModel = CoreMLModel.load(vadModelPath)
    val asrModel = CoreMLModel.load("$modelDir/sensevoice-500-itn.mlmodelc")
    val speakerModel = CoreMLModel.load("$modelDir/xvector.mlmodelc")

    val loadTime = kotlin.system.getTimeMillis() - startLoad
    println("${loadTime}ms")

    if (vadModel == null || asrModel == null || speakerModel == null) {
        println("  ERROR: Failed to load one or more models")
        return
    }

    // Read test audio file
    print("  Reading audio file... ")
    val audio = AudioFileReader.readFile(testAudioPath)
    if (audio == null) {
        println("FAILED - trying alternative file")
        // Try alternative
        val altAudio = AudioFileReader.readFile("/Users/zhengyishen/Codes/claude-code/voice/YouPu/Resources/recordings/test_recording.wav")
        if (altAudio == null) {
            println("  ERROR: No test audio files available")
            return
        }
        testFullPipelineWithAudio(altAudio, vadModel, asrModel, speakerModel)
        return
    }

    println("${audio.size} samples (${audio.size.toFloat() / SAMPLE_RATE}s)")
    testFullPipelineWithAudio(audio, vadModel, asrModel, speakerModel)
}

private fun testFullPipelineWithAudio(
    audio: FloatArray,
    vadModel: CoreMLModel,
    asrModel: CoreMLModel,
    speakerModel: CoreMLModel
) {
    val totalStart = kotlin.system.getTimeMillis()

    // Step 1: Run VAD to detect speech segments
    println("\n  Step 1: Voice Activity Detection")
    var vadStart = kotlin.system.getTimeMillis()

    var vadHidden = FloatArray(VAD_STATE_SIZE) { 0f }
    var vadCell = FloatArray(VAD_STATE_SIZE) { 0f }
    var vadContext = FloatArray(VAD_CONTEXT_SIZE) { 0f }

    val speechSegments = mutableListOf<Pair<Int, Int>>() // (start, end) in samples
    var isSpeaking = false
    var speechStart = 0
    var speechFrames = 0
    var silenceFrames = 0

    val minSpeechFrames = 3  // ~768ms minimum speech
    val minSilenceFrames = 2  // ~512ms to end speech

    var offset = 0
    var totalVadCalls = 0
    while (offset + VAD_CHUNK_SIZE <= audio.size) {
        // Prepare VAD input
        val vadInput = FloatArray(VAD_MODEL_INPUT_SIZE)
        for (i in 0 until VAD_CONTEXT_SIZE) {
            vadInput[i] = vadContext[i]
        }
        for (i in 0 until VAD_CHUNK_SIZE) {
            vadInput[VAD_CONTEXT_SIZE + i] = audio[offset + i]
        }

        // Update context
        for (i in 0 until VAD_CONTEXT_SIZE) {
            vadContext[i] = audio[offset + VAD_CHUNK_SIZE - VAD_CONTEXT_SIZE + i]
        }

        // Run VAD
        val vadOutput = vadModel.runVAD(vadInput, vadHidden, vadCell)
        totalVadCalls++

        if (vadOutput == null) {
            offset += VAD_CHUNK_SIZE
            continue
        }

        vadHidden = vadOutput.newHiddenState
        vadCell = vadOutput.newCellState

        val isSpeech = vadOutput.probability >= VAD_SPEECH_THRESHOLD

        if (isSpeech) {
            speechFrames++
            silenceFrames = 0
            if (!isSpeaking && speechFrames >= minSpeechFrames) {
                isSpeaking = true
                speechStart = maxOf(0, offset - (minSpeechFrames - 1) * VAD_CHUNK_SIZE)
            }
        } else {
            silenceFrames++
            speechFrames = 0
            if (isSpeaking && silenceFrames >= minSilenceFrames) {
                val speechEnd = offset + VAD_CHUNK_SIZE
                speechSegments.add(speechStart to speechEnd)
                isSpeaking = false
            }
        }

        offset += VAD_CHUNK_SIZE
    }

    // Handle trailing speech
    if (isSpeaking) {
        speechSegments.add(speechStart to audio.size)
    }

    val vadTime = kotlin.system.getTimeMillis() - vadStart
    println("    VAD calls: $totalVadCalls, time: ${vadTime}ms")
    println("    Speech segments found: ${speechSegments.size}")
    for ((i, seg) in speechSegments.withIndex()) {
        val duration = (seg.second - seg.first).toFloat() / SAMPLE_RATE
        println("      Segment ${i+1}: ${seg.first/SAMPLE_RATE.toFloat()}s - ${seg.second/SAMPLE_RATE.toFloat()}s (${duration}s)")
    }

    if (speechSegments.isEmpty()) {
        println("    No speech detected - skipping ASR")
        return
    }

    // Step 2: Process each speech segment with ASR
    println("\n  Step 2: Speech Recognition (ASR)")

    for ((segIdx, segment) in speechSegments.withIndex()) {
        val (segStart, segEnd) = segment
        val segmentAudio = audio.copyOfRange(segStart, minOf(segEnd, audio.size))

        if (segmentAudio.size < SAMPLE_RATE * MIN_SPEECH_DURATION) {
            println("    Segment ${segIdx+1}: Too short, skipping")
            continue
        }

        println("    Segment ${segIdx+1} (${segmentAudio.size} samples):")

        // Compute mel spectrogram
        val melStart = kotlin.system.getTimeMillis()
        val mel = AudioProcessing.computeMelSpectrogram(segmentAudio)
        val melTime = kotlin.system.getTimeMillis() - melStart
        println("      Mel spectrogram: ${mel.size} frames (${melTime}ms)")

        // Apply LFR
        val lfr = LFRTransform.apply(mel)
        val padded = LFRTransform.padToFixedFrames(lfr)
        println("      LFR features: ${padded.size} frames x ${padded[0].size} features")

        // Run ASR
        val asrStart = kotlin.system.getTimeMillis()
        val logits = asrModel.runASR(padded)
        val asrTime = kotlin.system.getTimeMillis() - asrStart

        if (logits == null) {
            println("      ASR inference failed")
            continue
        }

        println("      ASR inference: ${asrTime}ms (${logits.size} output frames)")

        // Decode tokens
        val tokens = CTCDecoder.greedyDecode(logits)
        val (info, textTokens) = TokenMappings.decodeSpecialTokens(tokens)

        println("      Language: ${info["language"]}, Emotion: ${info["emotion"]}")
        println("      Tokens (${textTokens.size}): ${textTokens.take(20)}${if (textTokens.size > 20) "..." else ""}")

        // Decode to text
        val text = TokenDecoder.decodeTextTokens(textTokens)
        println("      Text: $text")

        // Step 3: Speaker identification
        if (segmentAudio.size >= XVECTOR_SAMPLES) {
            val spkStart = kotlin.system.getTimeMillis()

            // Take center portion
            val center = (segmentAudio.size - XVECTOR_SAMPLES) / 2
            val xvectorInput = segmentAudio.copyOfRange(center, center + XVECTOR_SAMPLES)

            val embedding = speakerModel.runSpeakerEmbedding(xvectorInput)
            val spkTime = kotlin.system.getTimeMillis() - spkStart

            if (embedding != null) {
                println("      Speaker embedding: ${spkTime}ms (dim=${embedding.size})")
                println("      Embedding sample: [${embedding.take(5).joinToString(", ")}...]")
            }
        }
    }

    val totalTime = kotlin.system.getTimeMillis() - totalStart
    val audioDuration = audio.size.toFloat() / SAMPLE_RATE
    val rtf = totalTime / (audioDuration * 1000)

    println("\n  Summary:")
    println("    Audio duration: ${audioDuration}s")
    println("    Total processing time: ${totalTime}ms")
    println("    Real-time factor (RTF): ${rtf} (${if (rtf < 1) "faster" else "slower"} than real-time)")
}

private fun testVectorOps() {
    println("\n[Testing VectorOps]")

    val a = floatArrayOf(1f, 0f, 0f)
    val b = floatArrayOf(1f, 0f, 0f)
    val c = floatArrayOf(0f, 1f, 0f)

    val simAB = cosineSimilarity(a, b)
    val simAC = cosineSimilarity(a, c)

    println("  Similarity(a, b) = $simAB (expected: 1.0)")
    println("  Similarity(a, c) = $simAC (expected: 0.0)")

    check(simAB > 0.99f) { "Expected similarity 1.0" }
    check(simAC < 0.01f) { "Expected similarity 0.0" }

    println("  VectorOps: OK")
}

private fun testSpeakerProfile() {
    println("\n[Testing SpeakerProfile]")

    val profile = SpeakerProfile("Alice")

    // Add first embedding
    val emb1 = FloatArray(XVECTOR_DIM) { if (it == 0) 1f else 0f }
    val result1 = profile.addEmbedding(emb1)
    println("  First embedding: $result1 (expected: core)")
    check(result1 == "core") { "First embedding should go to core" }

    // Add similar embedding
    val emb2 = FloatArray(XVECTOR_DIM) { if (it == 0) 0.99f else if (it == 1) 0.1f else 0f }
    val result2 = profile.addEmbedding(emb2)
    println("  Similar embedding: $result2")

    // Check similarity
    val sim = profile.maxSimilarityToCore(emb1)
    println("  Max similarity to core: $sim")
    check(sim > 0.9f) { "Should have high similarity" }

    println("  SpeakerProfile: OK")
}

private fun testLFRTransform() {
    println("\n[Testing LFRTransform]")

    // Create fake mel spectrogram (20 frames of 80 features)
    val mel = List(20) { FloatArray(N_MELS) { 0.5f } }

    val lfr = LFRTransform.apply(mel)
    println("  Input frames: ${mel.size}")
    println("  LFR frames: ${lfr.size}")
    println("  LFR feature dim: ${lfr.firstOrNull()?.size ?: 0} (expected: $FEATURE_DIM)")

    check(lfr.isNotEmpty()) { "Should produce LFR frames" }
    check(lfr[0].size == FEATURE_DIM) { "LFR frame should have $FEATURE_DIM dimensions" }

    // Test padding
    val padded = LFRTransform.padToFixedFrames(lfr)
    println("  Padded frames: ${padded.size} (expected: $FIXED_FRAMES)")
    check(padded.size == FIXED_FRAMES) { "Should pad to $FIXED_FRAMES frames" }

    println("  LFRTransform: OK")
}

private fun testCTCDecoder() {
    println("\n[Testing CTCDecoder]")

    // Create fake logits (10 time steps, vocab size 100)
    val vocabSize = 100
    val logits = List(10) { t ->
        FloatArray(vocabSize) { v ->
            when {
                t < 3 && v == 0 -> 1f  // Blank for first 3 frames
                t >= 3 && t < 6 && v == 5 -> 1f  // Token 5 for frames 3-5
                t >= 6 && v == 10 -> 1f  // Token 10 for frames 6-9
                else -> 0f
            }
        }
    }

    val tokens = CTCDecoder.greedyDecode(logits)
    println("  Decoded tokens: $tokens (expected: [5, 10])")

    check(tokens.size == 2) { "Should decode to 2 tokens" }
    check(tokens[0] == 5) { "First token should be 5" }
    check(tokens[1] == 10) { "Second token should be 10" }

    // Test special token decoding
    val testTokens = listOf(24885, 5, 10, 24993)  // zh, 5, 10, NEUTRAL
    val (info, textTokens) = TokenMappings.decodeSpecialTokens(testTokens)
    println("  Special tokens: language=${info["language"]}, emotion=${info["emotion"]}")
    println("  Text tokens: $textTokens")

    check(info["language"] == "zh") { "Should detect Chinese" }
    check(info["emotion"] == "NEUTRAL") { "Should detect NEUTRAL emotion" }
    check(textTokens == listOf(5, 10)) { "Should extract text tokens" }

    println("  CTCDecoder: OK")
}

// ============================================================================
// Benchmark Functions
// ============================================================================

private fun benchmarkCoreML(audio: FloatArray, padded: List<FloatArray>, xvectorInput: FloatArray) {
    val numIterations = 5

    // Load models
    print("  Loading models... ")
    val loadStart = kotlin.system.getTimeMillis()
    val vadModel = CoreMLModel.load(VAD_MODEL_PATH)
    val asrModel = CoreMLModel.load("$MODEL_DIR/sensevoice-500-itn.mlmodelc")
    val speakerModel = CoreMLModel.load("$MODEL_DIR/xvector.mlmodelc")
    val loadTime = kotlin.system.getTimeMillis() - loadStart
    println("${loadTime}ms")

    if (vadModel == null || asrModel == null || speakerModel == null) {
        println("  ERROR: Failed to load CoreML models")
        return
    }

    // Warmup
    print("  Warmup... ")
    vadModel.runVAD(FloatArray(VAD_MODEL_INPUT_SIZE), FloatArray(VAD_STATE_SIZE), FloatArray(VAD_STATE_SIZE))
    asrModel.runASR(padded)
    speakerModel.runSpeakerEmbedding(xvectorInput)
    println("done")

    // Benchmark VAD
    val vadTimes = mutableListOf<Long>()
    for (i in 0 until numIterations) {
        val start = kotlin.system.getTimeMillis()
        var vadHidden = FloatArray(VAD_STATE_SIZE)
        var vadCell = FloatArray(VAD_STATE_SIZE)
        var vadContext = FloatArray(VAD_CONTEXT_SIZE)
        var offset = 0
        while (offset + VAD_CHUNK_SIZE <= audio.size) {
            val vadInput = FloatArray(VAD_MODEL_INPUT_SIZE)
            for (j in 0 until VAD_CONTEXT_SIZE) vadInput[j] = vadContext[j]
            for (j in 0 until VAD_CHUNK_SIZE) vadInput[VAD_CONTEXT_SIZE + j] = audio[offset + j]
            for (j in 0 until VAD_CONTEXT_SIZE) vadContext[j] = audio[offset + VAD_CHUNK_SIZE - VAD_CONTEXT_SIZE + j]

            val output = vadModel.runVAD(vadInput, vadHidden, vadCell)
            if (output != null) {
                vadHidden = output.newHiddenState
                vadCell = output.newCellState
            }
            offset += VAD_CHUNK_SIZE
        }
        vadTimes.add(kotlin.system.getTimeMillis() - start)
    }

    // Benchmark ASR
    val asrTimes = mutableListOf<Long>()
    for (i in 0 until numIterations) {
        val start = kotlin.system.getTimeMillis()
        asrModel.runASR(padded)
        asrTimes.add(kotlin.system.getTimeMillis() - start)
    }

    // Benchmark Speaker
    val spkTimes = mutableListOf<Long>()
    for (i in 0 until numIterations) {
        val start = kotlin.system.getTimeMillis()
        speakerModel.runSpeakerEmbedding(xvectorInput)
        spkTimes.add(kotlin.system.getTimeMillis() - start)
    }

    val vadAvg = vadTimes.average()
    val asrAvg = asrTimes.average()
    val spkAvg = spkTimes.average()

    println("  Model Load:      ${loadTime}ms")
    println("  VAD (full file): ${vadAvg.toLong()}ms avg (${vadTimes.joinToString(", ")})")
    println("  ASR:             ${asrAvg.toLong()}ms avg (${asrTimes.joinToString(", ")})")
    println("  Speaker:         ${spkAvg.toLong()}ms avg (${spkTimes.joinToString(", ")})")
    println("  Total inference: ${(vadAvg + asrAvg + spkAvg).toLong()}ms avg")
}

private fun benchmarkONNX(audio: FloatArray, padded: List<FloatArray>, xvectorInput: FloatArray) {
    val numIterations = 5

    // Load models
    print("  Loading models... ")
    val loadStart = kotlin.system.getTimeMillis()
    val onnxManager = ONNXModelManager(ONNX_MODEL_DIR)
    if (!onnxManager.loadModels()) {
        println("FAILED")
        return
    }
    val loadTime = kotlin.system.getTimeMillis() - loadStart
    println("${loadTime}ms")

    // ONNX VAD uses 512-sample chunks (32ms)
    val onnxVadChunkSize = ONNXModelManager.ONNX_VAD_CHUNK_SIZE

    // Warmup
    print("  Warmup... ")
    onnxManager.runVAD(FloatArray(onnxVadChunkSize), FloatArray(VAD_STATE_SIZE), FloatArray(VAD_STATE_SIZE))
    onnxManager.runASR(padded)
    onnxManager.runSpeakerEmbedding(xvectorInput)
    println("done")

    // Benchmark VAD (using 512-sample chunks for ONNX)
    val vadTimes = mutableListOf<Long>()
    for (i in 0 until numIterations) {
        val start = kotlin.system.getTimeMillis()
        var vadHidden = FloatArray(VAD_STATE_SIZE)
        var vadCell = FloatArray(VAD_STATE_SIZE)
        var offset = 0
        while (offset + onnxVadChunkSize <= audio.size) {
            val vadInput = audio.copyOfRange(offset, offset + onnxVadChunkSize)

            val output = onnxManager.runVAD(vadInput, vadHidden, vadCell)
            if (output != null) {
                vadHidden = output.hiddenState
                vadCell = output.cellState
            }
            offset += onnxVadChunkSize
        }
        vadTimes.add(kotlin.system.getTimeMillis() - start)
    }

    // Benchmark ASR
    val asrTimes = mutableListOf<Long>()
    for (i in 0 until numIterations) {
        val start = kotlin.system.getTimeMillis()
        onnxManager.runASR(padded)
        asrTimes.add(kotlin.system.getTimeMillis() - start)
    }

    // Benchmark Speaker
    val spkTimes = mutableListOf<Long>()
    for (i in 0 until numIterations) {
        val start = kotlin.system.getTimeMillis()
        onnxManager.runSpeakerEmbedding(xvectorInput)
        spkTimes.add(kotlin.system.getTimeMillis() - start)
    }

    val vadAvg = vadTimes.average()
    val asrAvg = asrTimes.average()
    val spkAvg = spkTimes.average()

    println("  Model Load:      ${loadTime}ms")
    println("  VAD (full file): ${vadAvg.toLong()}ms avg (${vadTimes.joinToString(", ")})")
    println("  ASR:             ${asrAvg.toLong()}ms avg (${asrTimes.joinToString(", ")})")
    println("  Speaker:         ${spkAvg.toLong()}ms avg (${spkTimes.joinToString(", ")})")
    println("  Total inference: ${(vadAvg + asrAvg + spkAvg).toLong()}ms avg")

    onnxManager.release()
}

// ============================================================================
// ONNX Processing Functions
// ============================================================================

@OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)
private fun runLiveTranscriptionONNX(onnxManager: ONNXModelManager, voiceLibraryPath: String) {
    val voiceLibrary = VoiceLibrary(voiceLibraryPath)

    // VAD state for ONNX (512-sample chunks)
    var vadHidden = FloatArray(VAD_STATE_SIZE)
    var vadCell = FloatArray(VAD_STATE_SIZE)

    // Audio buffers
    val audioBuffer = mutableListOf<Float>()
    val speechBuffer = mutableListOf<Float>()

    // Speech detection state
    var isSpeaking = false
    var silenceFrames = 0
    var speechFrames = 0
    var speechStartSample = 0L
    var totalSamplesProcessed = 0L

    // ONNX VAD uses 512-sample chunks
    val onnxVadChunk = ONNXModelManager.ONNX_VAD_CHUNK_SIZE
    val minSpeechFrames = (MIN_SPEECH_DURATION * SAMPLE_RATE / onnxVadChunk).toInt()
    val minSilenceFrames = (MIN_SILENCE_DURATION * SAMPLE_RATE / onnxVadChunk).toInt()

    // Segments collected
    val segments = mutableListOf<Segment>()

    println()
    println("=".repeat(60))
    println("LIVE TRANSCRIPTION (ONNX Runtime)")
    println("Press ESC to stop")
    println("=".repeat(60))
    println()

    // Audio callback
    fun processAudioChunk(samples: FloatArray) {
        for (s in samples) audioBuffer.add(s)

        // Process in 512-sample chunks for ONNX VAD
        while (audioBuffer.size >= onnxVadChunk) {
            val chunk = FloatArray(onnxVadChunk) { audioBuffer[it] }
            audioBuffer.subList(0, onnxVadChunk).clear()

            // Run VAD
            val vadOutput = onnxManager.runVAD(chunk, vadHidden, vadCell)
            if (vadOutput != null) {
                vadHidden = vadOutput.hiddenState
                vadCell = vadOutput.cellState

                val isSpeech = vadOutput.probability >= VAD_SPEECH_THRESHOLD

                if (isSpeech) {
                    speechFrames++
                    silenceFrames = 0
                    for (s in chunk) speechBuffer.add(s)

                    if (!isSpeaking && speechFrames >= minSpeechFrames) {
                        isSpeaking = true
                        speechStartSample = totalSamplesProcessed - (speechFrames * onnxVadChunk)
                    }
                } else {
                    silenceFrames++
                    speechFrames = 0

                    if (isSpeaking) {
                        if (silenceFrames <= minSilenceFrames) {
                            for (s in chunk) speechBuffer.add(s)
                        }

                        if (silenceFrames >= minSilenceFrames) {
                            // Process completed speech
                            val speechEndSample = totalSamplesProcessed
                            val audio = speechBuffer.toFloatArray()
                            speechBuffer.clear()

                            if (audio.size >= (SAMPLE_RATE * MIN_SPEECH_DURATION).toInt()) {
                                val processStart = kotlin.system.getTimeMillis()
                                val startTime = speechStartSample.toDouble() / SAMPLE_RATE
                                val endTime = speechEndSample.toDouble() / SAMPLE_RATE

                                // ASR
                                val mel = AudioProcessing.computeMelSpectrogram(audio)
                                val lfr = LFRTransform.apply(mel)
                                val padded = LFRTransform.padToFixedFrames(lfr)
                                val logitsRaw = onnxManager.runASR(padded)

                                var text = ""
                                if (logitsRaw != null) {
                                    val vocabSize = 25055
                                    val numFrames = logitsRaw.size / vocabSize
                                    val logits = List(numFrames) { f ->
                                        FloatArray(vocabSize) { v -> logitsRaw[f * vocabSize + v] }
                                    }
                                    val tokens = CTCDecoder.greedyDecode(logits)
                                    val (_, textTokens) = TokenMappings.decodeSpecialTokens(tokens)
                                    text = TokenDecoder.decodeTextTokens(textTokens)
                                }

                                // Speaker ID
                                var speakerName: String? = null
                                var confidence = "unknown"
                                var isKnown = false
                                var embedding: FloatArray? = null
                                var learned = false

                                if (audio.size >= XVECTOR_SAMPLES) {
                                    val center = (audio.size - XVECTOR_SAMPLES) / 2
                                    val xvectorInput = audio.copyOfRange(center, center + XVECTOR_SAMPLES)
                                    embedding = onnxManager.runSpeakerEmbedding(xvectorInput)

                                    if (embedding != null) {
                                        val (matchedName, score, matchConfidence) = voiceLibrary.match(embedding)
                                        confidence = matchConfidence
                                        if (matchedName != null) {
                                            speakerName = matchedName
                                            isKnown = true
                                            if (matchConfidence == "high") {
                                                learned = voiceLibrary.autoLearn(matchedName, embedding, score)
                                            }
                                        }
                                    }
                                }

                                val processTime = kotlin.system.getTimeMillis() - processStart

                                // Print output
                                val speakerTag = if (speakerName != null) "[$speakerName]" else "[Unknown]"
                                val timeRange = "(${formatTime(startTime)}-${formatTime(endTime)})"
                                val learnTag = if (learned) " *" else ""
                                println("$speakerTag $timeRange $text [${processTime}ms]$learnTag")

                                segments.add(Segment(startTime, endTime, text, speakerName, confidence, isKnown, false, embedding, processTime, learned))
                            }
                            isSpeaking = false
                        }
                    } else {
                        speechBuffer.clear()
                    }
                }
            }
            totalSamplesProcessed += onnxVadChunk
        }
    }

    // Set up audio capture
    val audioCapture = AudioCapture()
    globalShouldStop = false
    val originalTermios = setRawMode()

    audioCapture.start { samples ->
        if (!globalShouldStop) {
            processAudioChunk(samples)
        }
    }

    // Main loop - wait for ESC
    while (!globalShouldStop) {
        if (checkEscapeKey()) {
            globalShouldStop = true
        }
        platform.posix.usleep(50000u)
    }

    restoreTerminal(originalTermios)
    println("\n\nStopping...")

    audioCapture.stop()

    // Save voice library if we learned anything
    if (segments.any { it.learned }) {
        voiceLibrary.save()
        println("Voice library saved.")
    }

    if (segments.isEmpty()) {
        println("\nNo speech detected.")
    } else {
        println("\nProcessed ${segments.size} segments.")
    }

    onnxManager.release()
}

private fun formatTime(seconds: Double): String {
    val mins = (seconds / 60).toInt()
    val secs = seconds % 60
    val secsStr = ((secs * 100).toInt() / 100.0).toString()
    // Pad to 2 decimal places
    val parts = secsStr.split(".")
    val decimal = if (parts.size > 1) parts[1].padEnd(2, '0').take(2) else "00"
    val whole = parts[0].padStart(if (mins > 0) 2 else 1, '0')
    return if (mins > 0) {
        "$mins:$whole.$decimal"
    } else {
        "$whole.$decimal"
    }
}

private fun processFileTranscriptionONNX(audioPath: String, onnxManager: ONNXModelManager, voiceLibraryPath: String) {
    println("Processing file with ONNX: $audioPath")

    // Read audio file
    print("Reading audio... ")
    val audio = AudioFileReader.readFile(audioPath)
    if (audio == null) {
        println("FAILED")
        onnxManager.release()
        return
    }
    println("${audio.size} samples (${audio.size.toFloat() / SAMPLE_RATE}s)")

    // Process with VAD
    println("\nRunning VAD...")
    var vadHidden = FloatArray(VAD_STATE_SIZE)
    var vadCell = FloatArray(VAD_STATE_SIZE)
    var vadContext = FloatArray(VAD_CONTEXT_SIZE)

    val speechSegments = mutableListOf<Pair<Int, Int>>()
    var isSpeaking = false
    var speechStart = 0
    var speechFrames = 0
    var silenceFrames = 0
    val minSpeechFrames = 3
    val minSilenceFrames = 2

    var offset = 0
    while (offset + VAD_CHUNK_SIZE <= audio.size) {
        val vadInput = FloatArray(VAD_MODEL_INPUT_SIZE)
        for (i in 0 until VAD_CONTEXT_SIZE) vadInput[i] = vadContext[i]
        for (i in 0 until VAD_CHUNK_SIZE) vadInput[VAD_CONTEXT_SIZE + i] = audio[offset + i]
        for (i in 0 until VAD_CONTEXT_SIZE) vadContext[i] = audio[offset + VAD_CHUNK_SIZE - VAD_CONTEXT_SIZE + i]

        val output = onnxManager.runVAD(vadInput, vadHidden, vadCell)
        if (output != null) {
            vadHidden = output.hiddenState
            vadCell = output.cellState

            val isSpeech = output.probability >= VAD_SPEECH_THRESHOLD
            if (isSpeech) {
                speechFrames++
                silenceFrames = 0
                if (!isSpeaking && speechFrames >= minSpeechFrames) {
                    isSpeaking = true
                    speechStart = maxOf(0, offset - (minSpeechFrames - 1) * VAD_CHUNK_SIZE)
                }
            } else {
                silenceFrames++
                speechFrames = 0
                if (isSpeaking && silenceFrames >= minSilenceFrames) {
                    speechSegments.add(speechStart to offset + VAD_CHUNK_SIZE)
                    isSpeaking = false
                }
            }
        }
        offset += VAD_CHUNK_SIZE
    }
    if (isSpeaking) speechSegments.add(speechStart to audio.size)

    println("Found ${speechSegments.size} speech segments")

    // Process each segment
    for ((idx, segment) in speechSegments.withIndex()) {
        val (start, end) = segment
        val segmentAudio = audio.copyOfRange(start, minOf(end, audio.size))
        println("\nSegment ${idx + 1}: ${start.toFloat()/SAMPLE_RATE}s - ${end.toFloat()/SAMPLE_RATE}s")

        if (segmentAudio.size < SAMPLE_RATE * MIN_SPEECH_DURATION) {
            println("  Too short, skipping")
            continue
        }

        // Compute features and run ASR
        val mel = AudioProcessing.computeMelSpectrogram(segmentAudio)
        val lfr = LFRTransform.apply(mel)
        val padded = LFRTransform.padToFixedFrames(lfr)

        val logitsRaw = onnxManager.runASR(padded)
        if (logitsRaw == null) {
            println("  ASR failed")
            continue
        }

        // Convert flat array to 2D
        val vocabSize = 25055
        val numFrames = logitsRaw.size / vocabSize
        val logits = List(numFrames) { f ->
            FloatArray(vocabSize) { v -> logitsRaw[f * vocabSize + v] }
        }

        val tokens = CTCDecoder.greedyDecode(logits)
        val (info, textTokens) = TokenMappings.decodeSpecialTokens(tokens)
        val text = TokenDecoder.decodeTextTokens(textTokens)

        println("  Language: ${info["language"]}, Emotion: ${info["emotion"]}")
        println("  Text: $text")

        // Speaker embedding
        if (segmentAudio.size >= XVECTOR_SAMPLES) {
            val center = (segmentAudio.size - XVECTOR_SAMPLES) / 2
            val xvectorIn = segmentAudio.copyOfRange(center, center + XVECTOR_SAMPLES)
            val embedding = onnxManager.runSpeakerEmbedding(xvectorIn)
            if (embedding != null) {
                println("  Speaker embedding: dim=${embedding.size}")
            }
        }
    }

    onnxManager.release()
}
