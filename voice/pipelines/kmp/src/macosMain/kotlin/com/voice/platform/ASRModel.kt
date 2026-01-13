package com.voice.platform

import com.voice.core.*
import kotlin.system.getTimeMillis

/**
 * ASR model types supported by the pipeline
 */
enum class ASRModelType {
    SENSEVOICE,
    WHISPER_TURBO
}

/**
 * Result from ASR inference
 */
data class ASRResult(
    val text: String,
    val tokens: List<Int>,
    val language: String? = null
)

/**
 * Interface for ASR models
 * Different models (SenseVoice, Whisper) implement this interface
 */
interface ASRModel {
    val modelType: ASRModelType

    /**
     * Transcribe audio samples directly
     * @param audio 16kHz mono audio samples
     * @return transcribed text and metadata
     */
    fun transcribe(audio: FloatArray): ASRResult?
}

/**
 * SenseVoice ASR model wrapper
 * Non-autoregressive CTC-based model
 */
class SenseVoiceASR(
    private val model: CoreMLModel,
    private val debug: Boolean = false
) : ASRModel {
    override val modelType = ASRModelType.SENSEVOICE

    override fun transcribe(audio: FloatArray): ASRResult? {
        var t0 = getTimeMillis()

        // Compute mel spectrogram
        val mel = AudioProcessing.computeMelSpectrogram(audio)
        val melTime = getTimeMillis() - t0

        t0 = getTimeMillis()
        // Apply LFR transform
        val lfr = LFRTransform.apply(mel)
        val padded = LFRTransform.padToFixedFrames(lfr)
        val lfrTime = getTimeMillis() - t0

        t0 = getTimeMillis()
        // Run ASR inference
        val logits = model.runASR(padded) ?: return null
        val inferenceTime = getTimeMillis() - t0

        t0 = getTimeMillis()
        // Decode tokens using CTC decoder
        val tokens = CTCDecoder.greedyDecode(logits)
        val (info, textTokens) = TokenMappings.decodeSpecialTokens(tokens)

        // Decode text using existing TokenDecoder (uses loaded vocabulary)
        val text = TokenDecoder.decodeTextTokens(textTokens)
        val decodeTime = getTimeMillis() - t0

        if (debug) {
            println("  [ASR Timing] mel=${melTime}ms lfr=${lfrTime}ms inference=${inferenceTime}ms decode=${decodeTime}ms")
        }

        return ASRResult(
            text = text,
            tokens = textTokens,
            language = info["language"]
        )
    }
}
