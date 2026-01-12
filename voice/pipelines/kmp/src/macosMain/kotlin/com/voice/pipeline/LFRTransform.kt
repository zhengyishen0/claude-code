package com.voice.pipeline

/**
 * Low Frame Rate (LFR) transform for SenseVoice ASR.
 *
 * Stacks LFR_M consecutive frames with stride LFR_N,
 * reducing temporal resolution while increasing feature dimension.
 *
 * Input: (T, N_MELS) mel spectrogram
 * Output: (T', FEATURE_DIM) where T' = (T - LFR_M) / LFR_N + 1
 */
object LFRTransform {

    /**
     * Apply LFR transform to mel spectrogram features.
     *
     * @param mel List of mel spectrogram frames, each of size N_MELS
     * @return List of LFR frames, each of size FEATURE_DIM (N_MELS * LFR_M = 560)
     */
    fun apply(mel: List<FloatArray>): List<FloatArray> {
        if (mel.isEmpty()) return emptyList()

        val lfrFrames = mutableListOf<FloatArray>()
        var i = 0

        while (i + LFR_M <= mel.size) {
            // Stack LFR_M consecutive frames
            val stacked = FloatArray(FEATURE_DIM)
            for (j in 0 until LFR_M) {
                val frame = mel[i + j]
                for (k in frame.indices) {
                    stacked[j * N_MELS + k] = frame[k]
                }
            }
            lfrFrames.add(stacked)
            i += LFR_N  // Advance by stride
        }

        return lfrFrames
    }

    /**
     * Pad or truncate features to exactly FIXED_FRAMES frames.
     *
     * @param features List of LFR frames
     * @return List of exactly FIXED_FRAMES frames, each of size FEATURE_DIM
     */
    fun padToFixedFrames(features: List<FloatArray>): List<FloatArray> {
        val result = mutableListOf<FloatArray>()

        // Copy existing frames (up to FIXED_FRAMES)
        for (i in 0 until minOf(features.size, FIXED_FRAMES)) {
            result.add(features[i].copyOf())
        }

        // Pad with zeros if needed
        while (result.size < FIXED_FRAMES) {
            result.add(FloatArray(FEATURE_DIM))
        }

        return result
    }

    /**
     * Apply LFR transform and pad to fixed frames in one call.
     */
    fun applyAndPad(mel: List<FloatArray>): List<FloatArray> {
        val lfr = apply(mel)
        return padToFixedFrames(lfr)
    }
}
