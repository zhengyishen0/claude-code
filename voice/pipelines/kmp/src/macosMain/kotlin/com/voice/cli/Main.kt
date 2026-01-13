package com.voice.cli

import com.voice.core.*
import com.voice.platform.*

fun main(args: Array<String>) {
    val useOnnx = args.contains("--onnx")
    val useWhisper = args.contains("--whisper")
    val backend = if (useOnnx) Backend.ONNX else Backend.COREML
    val asrType = if (useWhisper) ASRModelType.WHISPER_TURBO else ASRModelType.SENSEVOICE
    val filteredArgs = args.filter { it != "--onnx" && it != "--whisper" }

    when {
        filteredArgs.isEmpty() -> showHelp()
        filteredArgs[0] == "test" -> runTests()
        filteredArgs[0] == "live" -> runLive(backend, asrType)
        filteredArgs[0] == "file" && filteredArgs.size > 1 -> runFile(filteredArgs[1], backend, asrType)
        filteredArgs[0] == "benchmark" && filteredArgs.size > 1 -> runBenchmark(filteredArgs[1])
        filteredArgs[0] == "benchmark" -> runBenchmark(null)
        filteredArgs[0] == "models" -> showModels()
        else -> showHelp()
    }
}

private fun showHelp() {
    println("""
KMP Voice Pipeline - macOS
==========================

Usage:
  kmp-pipeline test                 Run all tests
  kmp-pipeline live [options]       Start live transcription (press ESC to stop)
  kmp-pipeline file <path> [opts]   Process audio file
  kmp-pipeline benchmark [path]     Compare CoreML vs ONNX performance
  kmp-pipeline models               Show available ASR models

Options:
  --onnx      Use ONNX Runtime instead of CoreML (default: CoreML)
  --whisper   Use Whisper Turbo ASR model (default: SenseVoice)

ASR Models:
  SenseVoice  Fast non-autoregressive model (~0.045x RTF)
  Whisper     OpenAI Whisper Turbo (~0.6x RTF, higher accuracy)

Examples:
  ./build/bin/macos/debugExecutable/kmp-pipeline.kexe live
  ./build/bin/macos/debugExecutable/kmp-pipeline.kexe live --whisper
  ./build/bin/macos/debugExecutable/kmp-pipeline.kexe file recording.wav --whisper
  ./build/bin/macos/debugExecutable/kmp-pipeline.kexe models
    """.trimIndent())
}

private fun showModels() {
    println("""
Available ASR Models
====================

1. SenseVoice (default)
   - Type: Non-autoregressive CTC
   - Speed: ~0.045x RTF (22x faster than real-time)
   - Size: ~448MB
   - Languages: Chinese, English, Japanese, Korean, Cantonese
   - Use: Default, great for real-time transcription

2. Whisper Turbo (--whisper)
   - Type: Encoder-decoder (autoregressive)
   - Speed: ~0.6x RTF (1.7x faster than real-time)
   - Size: ~632MB
   - Languages: 99+ languages
   - Use: Higher accuracy, better for complex audio

To switch models, use the --whisper flag:
  kmp-pipeline live --whisper
  kmp-pipeline file audio.wav --whisper
    """.trimIndent())
}

private fun runLive(backend: Backend, asrType: ASRModelType) {
    val asrName = if (asrType == ASRModelType.WHISPER_TURBO) "Whisper Turbo" else "SenseVoice"
    println("KMP Voice Pipeline - Live Mode (${backend.name}, $asrName)")
    println("=" .repeat(50))

    // Load vocabulary (only needed for SenseVoice)
    if (asrType == ASRModelType.SENSEVOICE) {
        val vocabPath = "$ASSETS_DIR/vocab.json"
        if (!TokenDecoder.loadVocabulary(vocabPath)) {
            println("Warning: Could not load vocabulary from $vocabPath")
        }

        // Load mel filterbank
        val filterbankPath = "$ASSETS_DIR/mel_filterbank.bin"
        AudioProcessing.loadMelFilterbank(filterbankPath)
    }

    when (backend) {
        Backend.COREML -> runLiveWithCoreML(asrType)
        Backend.ONNX -> {
            if (asrType == ASRModelType.WHISPER_TURBO) {
                println("ERROR: Whisper model is only available with CoreML backend")
                return
            }
            runLiveWithONNX()
        }
    }
}

private fun runLiveWithCoreML(asrType: ASRModelType) {
    // Load CoreML models
    print("Loading CoreML models... ")
    val startLoad = kotlin.system.getTimeMillis()

    val vadModel = CoreMLModel.load(VAD_MODEL_PATH)
    val speakerModel = CoreMLModel.load("$MODEL_DIR/xvector.mlmodelc")

    // Load ASR model based on type
    val asrModel: ASRModel? = when (asrType) {
        ASRModelType.SENSEVOICE -> {
            val model = CoreMLModel.load("$MODEL_DIR/sensevoice-500-itn.mlmodelc")
            model?.let { SenseVoiceASR(it, SenseVoiceTokenizer("")) }
        }
        ASRModelType.WHISPER_TURBO -> {
            println()
            print("  Loading Whisper Turbo... ")
            WhisperASR.load(WHISPER_TURBO_MODEL_DIR)
        }
    }

    val loadTime = kotlin.system.getTimeMillis() - startLoad
    println("${loadTime}ms")

    if (vadModel == null || asrModel == null || speakerModel == null) {
        println("ERROR: Failed to load one or more CoreML models")
        return
    }

    println("ASR Model: ${asrModel.modelType}")

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

private fun runFile(audioPath: String, backend: Backend, asrType: ASRModelType) {
    val asrName = if (asrType == ASRModelType.WHISPER_TURBO) "Whisper Turbo" else "SenseVoice"
    println("KMP Voice Pipeline - File Mode (${backend.name}, $asrName)")
    println("=" .repeat(50))

    // Load vocabulary (only needed for SenseVoice)
    if (asrType == ASRModelType.SENSEVOICE) {
        val vocabPath = "$ASSETS_DIR/vocab.json"
        if (!TokenDecoder.loadVocabulary(vocabPath)) {
            println("Warning: Could not load vocabulary from $vocabPath")
        }

        // Load mel filterbank
        val filterbankPath = "$ASSETS_DIR/mel_filterbank.bin"
        AudioProcessing.loadMelFilterbank(filterbankPath)
    }

    when (backend) {
        Backend.COREML -> runFileWithCoreML(audioPath, asrType)
        Backend.ONNX -> {
            if (asrType == ASRModelType.WHISPER_TURBO) {
                println("ERROR: Whisper model is only available with CoreML backend")
                return
            }
            runFileWithONNX(audioPath)
        }
    }
}

private fun runFileWithCoreML(audioPath: String, asrType: ASRModelType) {
    // Load CoreML models
    print("Loading CoreML models... ")
    val startLoad = kotlin.system.getTimeMillis()

    val vadModel = CoreMLModel.load(VAD_MODEL_PATH)
    val speakerModel = CoreMLModel.load("$MODEL_DIR/xvector.mlmodelc")

    // Load ASR model based on type
    val asrModel: ASRModel? = when (asrType) {
        ASRModelType.SENSEVOICE -> {
            val model = CoreMLModel.load("$MODEL_DIR/sensevoice-500-itn.mlmodelc")
            model?.let { SenseVoiceASR(it, SenseVoiceTokenizer("")) }
        }
        ASRModelType.WHISPER_TURBO -> {
            println()
            print("  Loading Whisper Turbo... ")
            WhisperASR.load(WHISPER_TURBO_MODEL_DIR)
        }
    }

    val loadTime = kotlin.system.getTimeMillis() - startLoad
    println("${loadTime}ms")

    if (vadModel == null || asrModel == null || speakerModel == null) {
        println("ERROR: Failed to load one or more CoreML models")
        return
    }

    println("ASR Model: ${asrModel.modelType}")

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

// ============================================================================
// ONNX Processing Functions
// ============================================================================

@OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)
private fun runLiveTranscriptionONNX(onnxManager: ONNXModelManager, voiceLibraryPath: String) {
    val voiceLibrary = VoiceLibrary(voiceLibraryPath)

    // Reset VAD context state
    onnxManager.resetVADState()

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

    // Debug: track VAD calls
    var vadCallCount = 0
    var lastPrintTime = kotlin.system.getTimeMillis()

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
                vadCallCount++

                // Debug: print VAD probability every 2 seconds or when speech detected
                val now = kotlin.system.getTimeMillis()
                val rms = kotlin.math.sqrt(chunk.map { it * it }.average().toFloat())
                if (vadOutput.probability > 0.3 || now - lastPrintTime > 2000) {
                    print("\r[DEBUG] prob: ${vadOutput.probability}, rms: $rms, speaking: $isSpeaking, frames: $speechFrames     ")
                    lastPrintTime = now
                }

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
    onnxManager.resetVADState()  // Reset context state
    var vadHidden = FloatArray(VAD_STATE_SIZE)
    var vadCell = FloatArray(VAD_STATE_SIZE)

    // ONNX VAD uses 512-sample chunks
    val onnxVadChunkSize = ONNXModelManager.ONNX_VAD_CHUNK_SIZE

    val speechSegments = mutableListOf<Pair<Int, Int>>()
    var isSpeaking = false
    var speechStart = 0
    var speechFrames = 0
    var silenceFrames = 0
    // Adjust min frames for smaller ONNX chunk size (512 vs 4096)
    val minSpeechFrames = (MIN_SPEECH_DURATION * SAMPLE_RATE / onnxVadChunkSize).toInt()
    val minSilenceFrames = (MIN_SILENCE_DURATION * SAMPLE_RATE / onnxVadChunkSize).toInt()

    var offset = 0
    while (offset + onnxVadChunkSize <= audio.size) {
        val vadInput = audio.copyOfRange(offset, offset + onnxVadChunkSize)

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
                    speechStart = maxOf(0, offset - (minSpeechFrames - 1) * onnxVadChunkSize)
                }
            } else {
                silenceFrames++
                speechFrames = 0
                if (isSpeaking && silenceFrames >= minSilenceFrames) {
                    speechSegments.add(speechStart to offset + onnxVadChunkSize)
                    isSpeaking = false
                }
            }
        }
        offset += onnxVadChunkSize
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
