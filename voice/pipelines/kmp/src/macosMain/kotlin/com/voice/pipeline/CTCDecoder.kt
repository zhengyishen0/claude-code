package com.voice.pipeline

/**
 * CTC (Connectionist Temporal Classification) greedy decoder.
 *
 * Decodes logits from ASR model by:
 * 1. Taking argmax at each time step
 * 2. Removing blank tokens (index 0)
 * 3. Removing consecutive duplicate tokens
 */
object CTCDecoder {

    /**
     * Greedy decode logits to token IDs.
     *
     * @param logits List of probability distributions, shape (T, vocab_size)
     * @return List of decoded token IDs
     */
    fun greedyDecode(logits: List<FloatArray>): List<Int> {
        val tokens = mutableListOf<Int>()
        var prevToken = -1

        for (frame in logits) {
            // Find argmax
            var maxIdx = 0
            var maxVal = frame[0]
            for (i in 1 until frame.size) {
                if (frame[i] > maxVal) {
                    maxVal = frame[i]
                    maxIdx = i
                }
            }

            // Skip blanks (index 0) and consecutive duplicates
            if (maxIdx != 0 && maxIdx != prevToken) {
                tokens.add(maxIdx)
            }
            prevToken = maxIdx
        }

        return tokens
    }
}

/**
 * Token mappings for SenseVoice special tokens.
 */
object TokenMappings {

    // Language tokens
    val LANG_TOKENS = mapOf(
        24884 to "auto",
        24885 to "zh",
        24886 to "en",
        24887 to "yue",
        24888 to "ja",
        24889 to "ko"
    )

    // Task tokens
    val TASK_TOKENS = mapOf(
        25004 to "transcribe",
        25005 to "translate"
    )

    // Emotion tokens
    val EMOTION_TOKENS = mapOf(
        24993 to "NEUTRAL",
        24994 to "HAPPY",
        24995 to "SAD",
        24996 to "ANGRY"
    )

    // Event tokens
    val EVENT_TOKENS = mapOf(
        25016 to "Speech",
        25017 to "Applause",
        25018 to "BGM",
        25019 to "Laughter"
    )

    /**
     * Decode special tokens from token ID list.
     * Returns metadata and remaining text tokens.
     */
    fun decodeSpecialTokens(tokens: List<Int>): Pair<Map<String, String>, List<Int>> {
        val info = mutableMapOf<String, String>()
        val textTokens = mutableListOf<Int>()

        for (tok in tokens) {
            when {
                LANG_TOKENS.containsKey(tok) -> info["language"] = LANG_TOKENS[tok]!!
                TASK_TOKENS.containsKey(tok) -> info["task"] = TASK_TOKENS[tok]!!
                EMOTION_TOKENS.containsKey(tok) -> info["emotion"] = EMOTION_TOKENS[tok]!!
                EVENT_TOKENS.containsKey(tok) -> info["event"] = EVENT_TOKENS[tok]!!
                else -> textTokens.add(tok)
            }
        }

        return Pair(info, textTokens)
    }

    /**
     * Check if a token is a special token.
     */
    fun isSpecialToken(token: Int): Boolean {
        return LANG_TOKENS.containsKey(token) ||
                TASK_TOKENS.containsKey(token) ||
                EMOTION_TOKENS.containsKey(token) ||
                EVENT_TOKENS.containsKey(token)
    }
}
