package com.voice.pipeline

import kotlinx.cinterop.*
import platform.Foundation.*
import platform.posix.memcpy
import kotlin.math.*
import kissfft.*

/**
 * Audio processing utilities for voice pipeline
 * Implements mel spectrogram computation matching Python/Swift pipeline
 */
@OptIn(ExperimentalForeignApi::class)
object AudioProcessing {

    // Precomputed Hamming window
    private val hammingWindow: FloatArray by lazy {
        FloatArray(N_FFT) { n ->
            (0.54f - 0.46f * cos(2.0 * PI * n / (N_FFT - 1))).toFloat()
        }
    }

    // Mel filterbank (loaded from file or computed)
    private var melFilterbank: List<FloatArray>? = null

    // KissFFT config (lazily initialized)
    private var fftConfig: kiss_fftr_cfg? = null

    private fun getFFTConfig(): kiss_fftr_cfg {
        if (fftConfig == null) {
            fftConfig = kiss_fftr_alloc(N_FFT, 0, null, null)
        }
        return fftConfig!!
    }

    /**
     * Load mel filterbank from binary file (exported from torchaudio)
     * Shape: (201 bins, 80 mels) stored as row-major float32
     */
    fun loadMelFilterbank(path: String): Boolean {
        val data = NSData.dataWithContentsOfFile(path) ?: return false

        val numBins = N_FFT / 2 + 1  // 201
        val numMels = N_MELS  // 80
        val expectedSize = numBins * numMels * 4  // float32 = 4 bytes

        if (data.length.toInt() != expectedSize) {
            println("Filterbank size mismatch: expected $expectedSize, got ${data.length}")
            return false
        }

        // Load as flat array
        val floats = FloatArray(numBins * numMels)
        memScoped {
            val ptr = data.bytes?.reinterpret<FloatVar>()
            if (ptr != null) {
                for (i in floats.indices) {
                    floats[i] = ptr[i]
                }
            }
        }

        // Reshape to List<FloatArray> - torchaudio saves as (bins, mels) row-major
        // We need filterbank[mel][bin] for dot product
        val filterbank = List(numMels) { mel ->
            FloatArray(numBins) { bin ->
                floats[bin * numMels + mel]
            }
        }

        melFilterbank = filterbank
        return true
    }

    /**
     * Create mel filterbank from scratch (fallback if file not found)
     */
    fun createMelFilterbank() {
        val numBins = N_FFT / 2 + 1
        val fMin = 0f
        val fMax = SAMPLE_RATE / 2f

        fun hzToMel(hz: Float): Float = 2595f * log10(1f + hz / 700f)
        fun melToHz(mel: Float): Float = 700f * (10f.pow(mel / 2595f) - 1f)

        val melMin = hzToMel(fMin)
        val melMax = hzToMel(fMax)

        // Create mel center frequencies
        val melPoints = FloatArray(N_MELS + 2) { i ->
            melMin + i * (melMax - melMin) / (N_MELS + 1)
        }

        // Convert to Hz frequencies
        val hzPoints = melPoints.map { melToHz(it) }

        // Frequency for each FFT bin
        val fftFreqs = (0 until numBins).map { it * SAMPLE_RATE.toFloat() / N_FFT }

        // Create filterbank using triangular filters
        val filterbank = List(N_MELS) { m ->
            val fLow = hzPoints[m]
            val fCenter = hzPoints[m + 1]
            val fHigh = hzPoints[m + 2]

            FloatArray(numBins) { k ->
                val freq = fftFreqs[k]
                when {
                    freq >= fLow && freq < fCenter && fCenter > fLow ->
                        (freq - fLow) / (fCenter - fLow)
                    freq >= fCenter && freq <= fHigh && fHigh > fCenter ->
                        (fHigh - freq) / (fHigh - fCenter)
                    else -> 0f
                }
            }
        }

        melFilterbank = filterbank
    }

    /**
     * Compute mel spectrogram from audio samples
     * Matches Python torchaudio.transforms.MelSpectrogram with power=1.0
     */
    fun computeMelSpectrogram(audio: FloatArray): List<FloatArray> {
        // Ensure filterbank is loaded
        if (melFilterbank == null) {
            createMelFilterbank()
        }
        val filterbank = melFilterbank!!

        val frameLength = N_FFT
        val hopLength = HOP_LENGTH
        val halfN = frameLength / 2

        // Apply center padding (like torchaudio's center=True)
        val padLength = halfN
        val paddedAudio = FloatArray(audio.size + 2 * padLength)

        // Reflect padding at start
        for (i in 0 until padLength) {
            paddedAudio[padLength - 1 - i] = audio[minOf(i + 1, audio.size - 1)]
        }
        // Copy original audio
        for (i in audio.indices) {
            paddedAudio[padLength + i] = audio[i]
        }
        // Reflect padding at end
        for (i in 0 until padLength) {
            val srcIdx = audio.size - 2 - i
            paddedAudio[padLength + audio.size + i] = audio[maxOf(0, srcIdx)]
        }

        val numFrames = maxOf(1, (paddedAudio.size - frameLength) / hopLength + 1)
        val melFrames = mutableListOf<FloatArray>()

        // Process each frame
        for (i in 0 until numFrames) {
            val start = i * hopLength
            val end = minOf(start + frameLength, paddedAudio.size)

            // Extract and window frame
            val frame = FloatArray(frameLength)
            for (j in 0 until minOf(end - start, frameLength)) {
                frame[j] = paddedAudio[start + j] * hammingWindow[j]
            }

            // Compute FFT magnitude
            val magnitude = computeFFTMagnitude(frame)

            // Apply mel filterbank
            val melEnergies = FloatArray(N_MELS)
            for (m in 0 until N_MELS) {
                var sum = 0f
                for (k in magnitude.indices) {
                    sum += magnitude[k] * filterbank[m][k]
                }
                melEnergies[m] = sum
            }

            // Log scale: log(max(x, 1e-10))
            for (m in 0 until N_MELS) {
                melEnergies[m] = ln(maxOf(melEnergies[m], 1e-10f))
            }

            melFrames.add(melEnergies)
        }

        return melFrames
    }

    /**
     * Compute FFT magnitude using KissFFT
     * O(N log N) complexity
     */
    private fun computeFFTMagnitude(frame: FloatArray): FloatArray {
        val n = frame.size
        val numBins = n / 2 + 1
        val magnitude = FloatArray(numBins)

        memScoped {
            // Allocate input buffer
            val input = allocArray<FloatVar>(n)
            for (i in 0 until n) {
                input[i] = frame[i]
            }

            // Allocate output buffer (complex)
            val output = allocArray<kiss_fft_cpx>(numBins)

            // Run FFT
            val cfg = getFFTConfig()
            kiss_fftr(cfg, input, output)

            // Compute magnitude
            for (k in 0 until numBins) {
                val real = output[k].r
                val imag = output[k].i
                magnitude[k] = sqrt(real * real + imag * imag)
            }
        }

        return magnitude
    }

    /**
     * Resample audio from source sample rate to target sample rate
     * Uses linear interpolation
     */
    fun resample(audio: FloatArray, sourceSR: Int, targetSR: Int): FloatArray {
        if (sourceSR == targetSR) return audio

        val ratio = targetSR.toDouble() / sourceSR
        val outputLength = (audio.size * ratio).toInt()
        val output = FloatArray(outputLength)

        for (i in 0 until outputLength) {
            val srcIndex = i / ratio
            val srcIndexInt = srcIndex.toInt()
            val frac = (srcIndex - srcIndexInt).toFloat()

            output[i] = if (srcIndexInt + 1 < audio.size) {
                audio[srcIndexInt] * (1 - frac) + audio[srcIndexInt + 1] * frac
            } else if (srcIndexInt < audio.size) {
                audio[srcIndexInt]
            } else {
                0f
            }
        }

        return output
    }

    /**
     * Compute RMS (root mean square) of audio samples
     */
    fun computeRMS(samples: FloatArray): Float {
        if (samples.isEmpty()) return 0f
        var sum = 0f
        for (s in samples) {
            sum += s * s
        }
        return sqrt(sum / samples.size)
    }
}
