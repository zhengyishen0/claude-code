package com.voice.platform

import kotlinx.cinterop.*
import platform.CoreML.*
import platform.Foundation.*
import kotlinx.serialization.json.*

/**
 * Whisper ASR model wrapper
 * Encoder-decoder architecture with autoregressive decoding
 */
@OptIn(ExperimentalForeignApi::class)
class WhisperASR private constructor(
    private val melModel: CoreMLModel,
    private val encoderModel: CoreMLModel,
    private val decoderModel: CoreMLModel,
    private val tokenizer: WhisperTokenizer,
    private val config: WhisperConfig
) : ASRModel {
    override val modelType = ASRModelType.WHISPER_TURBO

    companion object {
        // Whisper expects 30 seconds of audio at 16kHz
        private const val WHISPER_AUDIO_LENGTH = 30 * 16000  // 480000 samples

        /**
         * Load Whisper model from directory
         */
        fun load(modelDir: String): WhisperASR? {
            // Load config
            val configPath = "$modelDir/config.json"
            val generationConfigPath = "$modelDir/generation_config.json"
            val config = WhisperConfig.load(configPath, generationConfigPath) ?: run {
                println("Failed to load Whisper config")
                return null
            }

            // Load models
            val melModel = CoreMLModel.load("$modelDir/MelSpectrogram.mlmodelc") ?: run {
                println("Failed to load MelSpectrogram model")
                return null
            }

            val encoderModel = CoreMLModel.load("$modelDir/AudioEncoder.mlmodelc") ?: run {
                println("Failed to load AudioEncoder model")
                return null
            }

            val decoderModel = CoreMLModel.load("$modelDir/TextDecoder.mlmodelc") ?: run {
                println("Failed to load TextDecoder model")
                return null
            }

            // Load tokenizer
            val tokenizerPath = "$modelDir/tokenizer/models/openai/whisper-large-v3/tokenizer.json"
            val tokenizer = WhisperTokenizer.load(tokenizerPath) ?: run {
                println("Failed to load tokenizer")
                return null
            }

            println("    Whisper config: vocab=${config.vocabSize}, maxLength=${config.maxLength}")
            return WhisperASR(melModel, encoderModel, decoderModel, tokenizer, config)
        }
    }

    override fun transcribe(audio: FloatArray): ASRResult? {
        return memScoped {
            try {
                // Step 1: Compute mel spectrogram using CoreML model
                val melOutput = computeMelSpectrogram(audio) ?: run {
                    println("Failed to compute mel spectrogram")
                    return null
                }

                // Step 2: Encode audio
                val encoderOutput = runEncoder(melOutput) ?: run {
                    println("Failed to encode audio")
                    return null
                }

                // Step 3: Decode tokens autoregressively
                val tokens = runDecoder(encoderOutput) ?: run {
                    println("Failed to decode tokens")
                    return null
                }

                // Step 4: Convert tokens to text
                val text = tokenizer.decode(tokens)

                ASRResult(
                    text = text,
                    tokens = tokens,
                    language = detectLanguage(tokens)
                )
            } catch (e: Exception) {
                println("Whisper transcribe error: ${e.message}")
                null
            }
        }
    }

    /**
     * Compute mel spectrogram using Whisper's CoreML MelSpectrogram model
     */
    private fun computeMelSpectrogram(audio: FloatArray): MLMultiArray? {
        return memScoped {
            // Pad or truncate audio to 30 seconds
            val paddedAudio = when {
                audio.size >= WHISPER_AUDIO_LENGTH -> audio.copyOf(WHISPER_AUDIO_LENGTH)
                else -> FloatArray(WHISPER_AUDIO_LENGTH).also { padded ->
                    audio.copyInto(padded)
                }
            }

            // Create input array [1, 480000]
            val inputArray = CoreMLModel.createMLMultiArray(
                listOf(1, WHISPER_AUDIO_LENGTH),
                MLMultiArrayDataTypeFloat32
            ) ?: return null

            MLArrayUtils.copyFloatArray(paddedAudio, inputArray)

            // Run MelSpectrogram model
            val outputs = melModel.predict(mapOf("audio" to inputArray)) ?: return null

            // Return mel spectrogram features
            outputs["melspectrogram_features"]
        }
    }

    /**
     * Run audio encoder
     */
    private fun runEncoder(melInput: MLMultiArray): MLMultiArray? {
        val outputs = encoderModel.predict(mapOf("melspectrogram_features" to melInput)) ?: return null
        return outputs["encoder_output_embeds"]
    }

    /**
     * Run autoregressive decoder
     */
    private fun runDecoder(encoderOutput: MLMultiArray): List<Int>? {
        return memScoped {
            val tokens = mutableListOf<Int>()
            val maxTokens = config.maxLength

            // Start with SOT token followed by language and task tokens
            tokens.add(config.decoderStartTokenId)  // <|startoftranscript|>
            tokens.add(config.langToId["<|en|>"] ?: 50259)  // Default to English
            tokens.add(config.taskToId["transcribe"] ?: 50360)  // Transcribe task
            tokens.add(config.noTimestampsTokenId)  // No timestamps

            while (tokens.size < maxTokens) {
                // Create token input [1, seq_len] as Int32
                val tokenArray = CoreMLModel.createMLMultiArray(
                    listOf(1, tokens.size),
                    MLMultiArrayDataTypeInt32
                ) ?: return null

                for (i in tokens.indices) {
                    MLArrayUtils.setInt(tokenArray, i, tokens[i])
                }

                // Run decoder
                val outputs = decoderModel.predict(mapOf(
                    "encoder_output_embeds" to encoderOutput,
                    "input_ids" to tokenArray
                )) ?: return null

                // Get logits for next token
                val logits = outputs["logits"] ?: return null

                // Get next token (greedy decoding - take argmax of last position)
                val nextToken = getNextToken(logits, tokens.size - 1)

                // Check for end of sequence
                if (nextToken == config.eosTokenId) {
                    break
                }

                tokens.add(nextToken)
            }

            // Remove special tokens from result (SOT, language, task, no_timestamps)
            tokens.drop(4)
        }
    }

    /**
     * Get next token from logits using greedy decoding
     */
    private fun getNextToken(logits: MLMultiArray, position: Int): Int {
        val shape = MLArrayUtils.getShape(logits)
        val strides = MLArrayUtils.getStrides(logits)

        // Logits shape is [batch, seq_len, vocab_size]
        val vocabSize = shape.last()
        val posStride = strides[1]
        val vocabStride = strides[2]

        var maxValue = Float.NEGATIVE_INFINITY
        var maxIdx = 0

        for (v in 0 until vocabSize) {
            // Skip suppressed tokens
            if (v in config.suppressTokens) continue

            val idx = position * posStride + v * vocabStride
            val value = MLArrayUtils.getFloat(logits, idx)

            if (value > maxValue) {
                maxValue = value
                maxIdx = v
            }
        }

        return maxIdx
    }

    private fun detectLanguage(tokens: List<Int>): String? {
        for ((lang, id) in config.langToId) {
            if (id in tokens) {
                return lang.removePrefix("<|").removeSuffix("|>")
            }
        }
        return null
    }
}

/**
 * Whisper configuration loaded from config.json and generation_config.json
 */
data class WhisperConfig(
    val numMelBins: Int = 128,
    val maxSourcePositions: Int = 1500,
    val maxLength: Int = 448,
    val vocabSize: Int = 51866,
    val decoderStartTokenId: Int = 50258,
    val eosTokenId: Int = 50257,
    val noTimestampsTokenId: Int = 50364,
    val langToId: Map<String, Int> = emptyMap(),
    val taskToId: Map<String, Int> = emptyMap(),
    val suppressTokens: Set<Int> = emptySet()
) {
    companion object {
        @OptIn(ExperimentalForeignApi::class)
        fun load(configPath: String, generationConfigPath: String): WhisperConfig? {
            try {
                val configJson = NSString.stringWithContentsOfFile(configPath, NSUTF8StringEncoding, null)
                    ?: return null
                val genConfigJson = NSString.stringWithContentsOfFile(generationConfigPath, NSUTF8StringEncoding, null)
                    ?: return null

                val config = Json.parseToJsonElement(configJson.toString()).jsonObject
                val genConfig = Json.parseToJsonElement(genConfigJson.toString()).jsonObject

                val langToId = genConfig["lang_to_id"]?.jsonObject?.mapValues {
                    it.value.jsonPrimitive.int
                } ?: emptyMap()

                val taskToId = genConfig["task_to_id"]?.jsonObject?.mapValues {
                    it.value.jsonPrimitive.int
                } ?: emptyMap()

                val suppressTokens = genConfig["suppress_tokens"]?.jsonArray?.map {
                    it.jsonPrimitive.int
                }?.toSet() ?: emptySet()

                return WhisperConfig(
                    numMelBins = config["num_mel_bins"]?.jsonPrimitive?.int ?: 128,
                    maxSourcePositions = config["max_source_positions"]?.jsonPrimitive?.int ?: 1500,
                    maxLength = genConfig["max_length"]?.jsonPrimitive?.int ?: 448,
                    vocabSize = config["vocab_size"]?.jsonPrimitive?.int ?: 51866,
                    decoderStartTokenId = config["decoder_start_token_id"]?.jsonPrimitive?.int ?: 50258,
                    eosTokenId = config["eos_token_id"]?.jsonPrimitive?.int ?: 50257,
                    noTimestampsTokenId = genConfig["no_timestamps_token_id"]?.jsonPrimitive?.int ?: 50364,
                    langToId = langToId,
                    taskToId = taskToId,
                    suppressTokens = suppressTokens
                )
            } catch (e: Exception) {
                println("Failed to load Whisper config: ${e.message}")
                return null
            }
        }
    }
}

/**
 * Whisper tokenizer using HuggingFace tokenizer.json
 */
class WhisperTokenizer private constructor(
    private val vocab: Map<Int, String>
) {
    companion object {
        @OptIn(ExperimentalForeignApi::class)
        fun load(path: String): WhisperTokenizer? {
            try {
                val json = NSString.stringWithContentsOfFile(path, NSUTF8StringEncoding, null)
                    ?: return null

                val tokenizer = Json.parseToJsonElement(json.toString()).jsonObject
                val model = tokenizer["model"]?.jsonObject
                val vocabObj = model?.get("vocab")?.jsonObject

                // Build id -> token map
                val idToToken = mutableMapOf<Int, String>()
                vocabObj?.forEach { (token, id) ->
                    idToToken[id.jsonPrimitive.int] = token
                }

                println("    Whisper tokenizer: ${idToToken.size} tokens")
                return WhisperTokenizer(idToToken)
            } catch (e: Exception) {
                println("Failed to load Whisper tokenizer: ${e.message}")
                return null
            }
        }
    }

    fun decode(tokens: List<Int>): String {
        val result = StringBuilder()

        for (token in tokens) {
            val text = vocab[token] ?: continue

            // Skip special tokens
            if (text.startsWith("<|") && text.endsWith("|>")) continue

            // Handle Whisper's byte-level BPE encoding
            val decoded = text
                .replace("Ġ", " ")  // Space prefix
                .replace("Ċ", "\n") // Newline

            result.append(decoded)
        }

        return result.toString().trim()
    }
}
