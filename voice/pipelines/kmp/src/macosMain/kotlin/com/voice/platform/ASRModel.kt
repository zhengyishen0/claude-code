package com.voice.platform

import com.voice.core.*

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
    private val tokenizer: SenseVoiceTokenizer
) : ASRModel {
    override val modelType = ASRModelType.SENSEVOICE

    override fun transcribe(audio: FloatArray): ASRResult? {
        // Compute mel spectrogram
        val mel = AudioProcessing.computeMelSpectrogram(audio)

        // Apply LFR transform
        val lfr = LFRTransform.apply(mel)
        val padded = LFRTransform.padToFixedFrames(lfr)

        // Run ASR inference
        val logits = model.runASR(padded) ?: return null

        // Decode tokens using CTC decoder
        val tokens = CTCDecoder.greedyDecode(logits)
        val (info, textTokens) = TokenMappings.decodeSpecialTokens(tokens)

        // Decode text using tokenizer
        val text = tokenizer.decode(textTokens)

        return ASRResult(
            text = text,
            tokens = textTokens,
            language = info["language"]
        )
    }
}

/**
 * SenseVoice tokenizer (placeholder - would use SentencePiece)
 */
class SenseVoiceTokenizer(vocabPath: String) {
    // In a full implementation, this would load SentencePiece model
    // For now, return token IDs as string
    fun decode(tokens: List<Int>): String {
        return tokens.joinToString("") { "[$it]" }
    }
}
