package com.voice.pipeline

import kotlinx.cinterop.*
import platform.Foundation.*
import kotlinx.serialization.json.*

/**
 * Token decoder using exported vocabulary from SentencePiece
 * Converts token IDs to text strings
 */
@OptIn(ExperimentalForeignApi::class)
object TokenDecoder {
    private var vocabulary: Map<Int, String>? = null
    private val json = Json { ignoreUnknownKeys = true }

    /**
     * Load vocabulary from JSON file
     * Format: {"0": "<unk>", "1": "<s>", ...}
     */
    fun loadVocabulary(path: String): Boolean {
        val data = NSData.dataWithContentsOfFile(path) ?: run {
            println("Failed to read vocabulary file: $path")
            return false
        }

        val jsonString = NSString.create(data, NSUTF8StringEncoding) as String? ?: run {
            println("Failed to decode vocabulary as UTF-8")
            return false
        }

        return try {
            val jsonElement = json.parseToJsonElement(jsonString)
            val vocab = mutableMapOf<Int, String>()

            jsonElement.jsonObject.forEach { (key, value) ->
                val id = key.toIntOrNull() ?: return@forEach
                val token = value.jsonPrimitive.contentOrNull ?: return@forEach
                vocab[id] = token
            }

            vocabulary = vocab
            println("Loaded vocabulary: ${vocab.size} tokens")
            true
        } catch (e: Exception) {
            println("Failed to parse vocabulary: ${e.message}")
            false
        }
    }

    /**
     * Decode a list of token IDs to text
     * Note: SentencePiece uses ▁ (U+2581) for word boundaries
     */
    fun decode(tokenIds: List<Int>): String {
        val vocab = vocabulary ?: return tokenIds.joinToString(" ") { "[$it]" }

        val pieces = tokenIds.mapNotNull { id ->
            // No offset needed - Python-exported vocabulary uses direct token IDs
            vocab[id]
        }

        // Join pieces and convert ▁ to spaces
        return pieces.joinToString("")
            .replace("▁", " ")
            .trim()
    }

    /**
     * Decode tokens with special token filtering already applied
     */
    fun decodeTextTokens(textTokens: List<Int>): String {
        return decode(textTokens)
    }

    /**
     * Check if vocabulary is loaded
     */
    fun isLoaded(): Boolean = vocabulary != null

    /**
     * Get vocabulary size
     */
    fun vocabularySize(): Int = vocabulary?.size ?: 0
}
