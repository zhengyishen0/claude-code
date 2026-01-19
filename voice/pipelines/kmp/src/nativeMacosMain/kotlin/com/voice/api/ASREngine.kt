package com.voice.api

import com.voice.core.*
import com.voice.platform.*

/**
 * Public API for ASR inference - exposed to Swift via framework.
 *
 * Usage from Swift:
 * ```swift
 * let engine = ASREngine(modelDir: "/path/to/models/coreml",
 *                        assetsDir: "/path/to/models/assets")
 * engine.initialize()
 * let text = engine.transcribe(audio: floatArray)
 * ```
 */
class ASREngine(
    private val modelDir: String,
    private val assetsDir: String
) {
    private var asrModel: CoreMLModel? = null
    private var isInitialized = false

    /**
     * Initialize models. Call once at app startup.
     * @return true if initialization succeeded
     */
    fun initialize(): Boolean {
        if (isInitialized) return true

        // Load vocabulary for token decoding
        val vocabPath = "$assetsDir/vocab.json"
        val vocabLoaded = TokenDecoder.loadVocabulary(vocabPath)
        if (!vocabLoaded) {
            println("ASREngine: Failed to load vocabulary from $vocabPath")
            return false
        }

        // Load mel filterbank (with fallback to computed version)
        val filterbankPath = "$assetsDir/mel_filterbank.bin"
        val fbLoaded = AudioProcessing.loadMelFilterbank(filterbankPath)
        if (!fbLoaded) {
            println("ASREngine: Filterbank not found, using computed version")
            AudioProcessing.createMelFilterbank()
        }

        // Load CoreML ASR model
        val modelPath = "$modelDir/sensevoice-500-itn.mlmodelc"
        asrModel = CoreMLModel.load(modelPath)
        if (asrModel == null) {
            println("ASREngine: Failed to load ASR model from $modelPath")
            return false
        }

        isInitialized = true
        println("ASREngine: Initialized successfully")
        return true
    }

    /**
     * Transcribe audio samples to text.
     *
     * @param audio 16kHz mono float samples
     * @return transcribed text, or null if transcription failed
     */
    fun transcribe(audio: FloatArray): String? {
        val model = asrModel
        if (model == null) {
            println("ASREngine: Not initialized, call initialize() first")
            return null
        }

        // Step 1: Compute mel spectrogram
        val mel = AudioProcessing.computeMelSpectrogram(audio)

        // Step 2: Apply LFR transform and pad to fixed frames
        val features = LFRTransform.applyAndPad(mel)

        // Step 3: Run CoreML inference
        val logits = model.runASR(features)
        if (logits == null) {
            println("ASREngine: CoreML inference failed")
            return null
        }

        // Step 4: CTC greedy decode
        val tokens = CTCDecoder.greedyDecode(logits)

        // Step 5: Extract text tokens (remove special tokens)
        val (_, textTokens) = TokenMappings.decodeSpecialTokens(tokens)

        // Step 6: Decode tokens to text
        return TokenDecoder.decode(textTokens)
    }

    /**
     * Check if the engine is ready for transcription.
     */
    fun isReady(): Boolean = isInitialized && asrModel != null

    /**
     * Get the model directory path.
     */
    fun getModelDir(): String = modelDir

    /**
     * Get the assets directory path.
     */
    fun getAssetsDir(): String = assetsDir
}
