package com.voice.cli

import com.voice.core.*
import com.voice.platform.*

/**
 * Benchmark comparing CoreML vs ONNX performance
 */
fun runBenchmark(audioPath: String?) {
    println("KMP Voice Pipeline - Benchmark Mode")
    println("=" .repeat(40))

    // Load vocabulary
    val vocabPath = "$ASSETS_DIR/vocab.json"
    if (!TokenDecoder.loadVocabulary(vocabPath)) {
        println("Warning: Could not load vocabulary from $vocabPath")
    }

    // Load mel filterbank
    val filterbankPath = "$ASSETS_DIR/mel_filterbank.bin"
    AudioProcessing.loadMelFilterbank(filterbankPath)

    // Read test audio
    val testAudioPath = audioPath ?: TEST_AUDIO_PATH
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
        onnxManager.resetVADState()  // Reset context for each iteration
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
