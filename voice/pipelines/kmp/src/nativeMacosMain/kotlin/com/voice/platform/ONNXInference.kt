package com.voice.platform

import com.voice.core.*

import kotlinx.cinterop.*
import OnnxRuntime.*

/**
 * ONNX Runtime inference wrapper using C wrapper library
 * Note: OnnxSession is an opaque struct, so we use COpaquePointer
 */
@OptIn(ExperimentalForeignApi::class)
class ONNXModel(private val modelPath: String, private val modelName: String) {

    private var session: COpaquePointer? = null

    init {
        load()
    }

    private fun load() {
        session = onnx_create_session(modelPath)
        if (session == null) {
            val error = onnx_get_error()?.toKString() ?: "Unknown error"
            println("Failed to load ONNX model $modelName: $error")
        } else {
            println("Loaded ONNX model: $modelName")
        }
    }

    fun isLoaded(): Boolean = session != null

    fun release() {
        session?.let { onnx_destroy_session(it?.reinterpret()) }
        session = null
    }
}

/**
 * ONNX model manager for voice pipeline
 */
@OptIn(ExperimentalForeignApi::class)
class ONNXModelManager(private val modelsDir: String) {

    private var vadSession: COpaquePointer? = null
    private var asrSession: COpaquePointer? = null
    private var speakerSession: COpaquePointer? = null

    // Context buffer for VAD (last 64 samples from previous chunk)
    private var vadContext: FloatArray = FloatArray(ONNX_VAD_CONTEXT_SIZE) { 0f }

    fun loadModels(): Boolean {
        println("Initializing ONNX Runtime...")
        if (onnx_init() != 0) {
            println("Failed to initialize ONNX Runtime: ${onnx_get_error()?.toKString()}")
            return false
        }

        println("Loading ONNX models from $modelsDir...")

        vadSession = onnx_create_session("$modelsDir/silero_vad.onnx")
        if (vadSession == null) {
            println("Failed to load VAD: ${onnx_get_error()?.toKString()}")
        } else {
            println("  VAD model loaded")
        }

        asrSession = onnx_create_session("$modelsDir/sensevoice.onnx")
        if (asrSession == null) {
            println("Failed to load ASR: ${onnx_get_error()?.toKString()}")
        } else {
            println("  ASR model loaded")
        }

        speakerSession = onnx_create_session("$modelsDir/xvector.onnx")
        if (speakerSession == null) {
            println("Failed to load Speaker: ${onnx_get_error()?.toKString()}")
        } else {
            println("  Speaker model loaded")
        }

        return vadSession != null && asrSession != null && speakerSession != null
    }

    /**
     * VAD output data class
     */
    data class VADOutput(
        val probability: Float,
        val hiddenState: FloatArray,
        val cellState: FloatArray
    )

    companion object {
        // ONNX Silero VAD uses 512-sample chunks (32ms at 16kHz)
        const val ONNX_VAD_CHUNK_SIZE = 512
        // Context size: 64 samples prepended to each chunk
        const val ONNX_VAD_CONTEXT_SIZE = 64
        // Total input size: context + chunk = 576 samples
        const val ONNX_VAD_INPUT_SIZE = ONNX_VAD_CONTEXT_SIZE + ONNX_VAD_CHUNK_SIZE
    }

    /**
     * Reset VAD state (call when starting a new audio stream)
     */
    fun resetVADState() {
        vadContext = FloatArray(ONNX_VAD_CONTEXT_SIZE) { 0f }
    }

    /**
     * Run VAD inference on a 512-sample chunk.
     * Internally prepends 64 context samples (from previous chunk) to create 576-sample input.
     * The context is automatically updated after each call.
     */
    fun runVAD(audio: FloatArray, hiddenState: FloatArray, cellState: FloatArray): VADOutput? {
        val sess = vadSession ?: return null

        // Ensure we have exactly ONNX_VAD_CHUNK_SIZE samples
        val chunk = if (audio.size >= ONNX_VAD_CHUNK_SIZE) {
            audio.copyOfRange(0, ONNX_VAD_CHUNK_SIZE)
        } else {
            FloatArray(ONNX_VAD_CHUNK_SIZE) { i -> if (i < audio.size) audio[i] else 0f }
        }

        // Create input with context prepended: [context (64)] + [chunk (512)] = 576 samples
        val inputWithContext = FloatArray(ONNX_VAD_INPUT_SIZE)
        for (i in 0 until ONNX_VAD_CONTEXT_SIZE) {
            inputWithContext[i] = vadContext[i]
        }
        for (i in 0 until ONNX_VAD_CHUNK_SIZE) {
            inputWithContext[ONNX_VAD_CONTEXT_SIZE + i] = chunk[i]
        }

        // Update context for next call (last 64 samples of current chunk)
        for (i in 0 until ONNX_VAD_CONTEXT_SIZE) {
            vadContext[i] = chunk[ONNX_VAD_CHUNK_SIZE - ONNX_VAD_CONTEXT_SIZE + i]
        }

        memScoped {
            val audioPtr = allocArray<FloatVar>(ONNX_VAD_INPUT_SIZE)
            for (i in 0 until ONNX_VAD_INPUT_SIZE) audioPtr[i] = inputWithContext[i]

            val hInPtr = allocArray<FloatVar>(hiddenState.size)
            for (i in hiddenState.indices) hInPtr[i] = hiddenState[i]

            val cInPtr = allocArray<FloatVar>(cellState.size)
            for (i in cellState.indices) cInPtr[i] = cellState[i]

            val probOut = alloc<FloatVar>()
            val hOutPtr = allocArray<FloatVar>(128)
            val cOutPtr = allocArray<FloatVar>(128)

            val result = onnx_run_vad(
                sess?.reinterpret(),
                audioPtr, ONNX_VAD_INPUT_SIZE,
                hInPtr, cInPtr,
                probOut.ptr, hOutPtr, cOutPtr
            )

            if (result != 0) {
                println("VAD inference failed: ${onnx_get_error()?.toKString()}")
                return null
            }

            val newHidden = FloatArray(128) { hOutPtr[it] }
            val newCell = FloatArray(128) { cOutPtr[it] }

            return VADOutput(probOut.value, newHidden, newCell)
        }
    }

    /**
     * Run ASR inference
     */
    fun runASR(melLFR: List<FloatArray>): FloatArray? {
        val sess = asrSession ?: return null

        val frames = melLFR.size
        val features = if (melLFR.isNotEmpty()) melLFR[0].size else FEATURE_DIM

        memScoped {
            // Flatten input
            val inputPtr = allocArray<FloatVar>(frames * features)
            for (i in melLFR.indices) {
                for (j in melLFR[i].indices) {
                    inputPtr[i * features + j] = melLFR[i][j]
                }
            }

            // Allocate output buffer (frames * vocab_size, assume max 25000 vocab)
            val maxOutputSize = frames * 25055  // SenseVoice vocab size
            val outputPtr = allocArray<FloatVar>(maxOutputSize)

            val outputSize = onnx_run_asr(
                sess?.reinterpret(),
                inputPtr, frames, features,
                outputPtr, maxOutputSize
            )

            if (outputSize < 0) {
                println("ASR inference failed: ${onnx_get_error()?.toKString()}")
                return null
            }

            return FloatArray(outputSize) { outputPtr[it] }
        }
    }

    /**
     * Run speaker embedding inference
     * Note: xvector ONNX expects fbank features (frames, 24), not raw audio
     */
    fun runSpeakerEmbedding(audio: FloatArray): FloatArray? {
        val sess = speakerSession ?: return null

        // Compute fbank features from audio (24 mel bins, like SpeechBrain)
        val fbank = computeFbank(audio)
        val frames = fbank.size / 24

        memScoped {
            val inputPtr = allocArray<FloatVar>(fbank.size)
            for (i in fbank.indices) inputPtr[i] = fbank[i]

            val embeddingPtr = allocArray<FloatVar>(512)

            val result = onnx_run_speaker(sess?.reinterpret(), inputPtr, frames, embeddingPtr)

            if (result != 0) {
                println("Speaker inference failed: ${onnx_get_error()?.toKString()}")
                return null
            }

            return FloatArray(512) { embeddingPtr[it] }
        }
    }

    /**
     * Compute 24-bin fbank features from audio (simplified version)
     * SpeechBrain xvector uses 24 mel bins
     */
    private fun computeFbank(audio: FloatArray): FloatArray {
        // Use 25ms window, 10ms hop at 16kHz
        val windowSize = 400
        val hopSize = 160
        val numMels = 24

        val numFrames = maxOf(1, (audio.size - windowSize) / hopSize + 1)
        val fbank = FloatArray(numFrames * numMels)

        // Simplified fbank computation using existing AudioProcessing
        // For accurate results, we'd need to match SpeechBrain's exact implementation
        // Here we use our 80-bin mel and downsample to 24 bins

        val mel80 = AudioProcessing.computeMelSpectrogram(audio)

        for (frame in 0 until minOf(numFrames, mel80.size)) {
            // Downsample 80 bins to 24 bins by averaging groups
            val binRatio = 80.0 / numMels
            for (mel in 0 until numMels) {
                val startBin = (mel * binRatio).toInt()
                val endBin = minOf(80, ((mel + 1) * binRatio).toInt())
                var sum = 0f
                for (b in startBin until endBin) {
                    sum += mel80[frame][b]
                }
                fbank[frame * numMels + mel] = sum / (endBin - startBin)
            }
        }

        return fbank
    }

    fun release() {
        vadSession?.let { onnx_destroy_session(it.reinterpret()) }
        asrSession?.let { onnx_destroy_session(it.reinterpret()) }
        speakerSession?.let { onnx_destroy_session(it.reinterpret()) }
        vadSession = null
        asrSession = null
        speakerSession = null
        onnx_cleanup()
    }
}
