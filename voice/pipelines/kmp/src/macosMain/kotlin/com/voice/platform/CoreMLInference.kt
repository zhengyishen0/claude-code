package com.voice.platform

import com.voice.core.*

import kotlinx.cinterop.*
import platform.CoreML.*
import platform.Foundation.*

/**
 * CoreML model wrapper for voice pipeline inference
 */
@OptIn(ExperimentalForeignApi::class)
class CoreMLModel(val internalModel: MLModel) {
    // Keep private alias for backward compatibility
    private val model get() = internalModel

    companion object {
        /**
         * Load a CoreML model from a .mlmodelc directory
         */
        fun load(path: String): CoreMLModel? {
            val url = NSURL.fileURLWithPath(path)
            val config = MLModelConfiguration().apply {
                computeUnits = MLComputeUnitsAll
            }

            return memScoped {
                val errorPtr = alloc<ObjCObjectVar<NSError?>>()
                val model = MLModel.modelWithContentsOfURL(url, config, errorPtr.ptr)

                if (model != null) {
                    CoreMLModel(model)
                } else {
                    println("Failed to load model: ${errorPtr.value?.localizedDescription}")
                    null
                }
            }
        }

        /**
         * Create an MLMultiArray with given shape and data type
         * Uses deprecated initWithShape which is still functional
         */
        @Suppress("DEPRECATION_ERROR")
        fun createMLMultiArray(shape: List<Int>, dataType: MLMultiArrayDataType): MLMultiArray? {
            return memScoped {
                val nsShape = shape.map { NSNumber(int = it) }
                val errorPtr = alloc<ObjCObjectVar<NSError?>>()

                // Use alloc/initWithShape pattern
                val array = MLMultiArray.alloc()
                array?.initWithShape(nsShape, dataType, errorPtr.ptr)
            }
        }
    }

    /**
     * Run VAD inference
     * Input: audio (4160 samples), hidden state (128), cell state (128)
     * Output: probability, new hidden state, new cell state
     */
    fun runVAD(
        audioInput: FloatArray,
        hiddenState: FloatArray,
        cellState: FloatArray
    ): VADOutput? {
        return memScoped {
            try {
                // Create audio input array [1, 4160]
                val audioArray = createMLMultiArray(listOf(1, VAD_MODEL_INPUT_SIZE), MLMultiArrayDataTypeFloat32)
                    ?: return null
                copyFloatArrayToMLMultiArray(audioInput, audioArray)

                // Create hidden state array [1, 128]
                val hiddenArray = createMLMultiArray(listOf(1, VAD_STATE_SIZE), MLMultiArrayDataTypeFloat32)
                    ?: return null
                copyFloatArrayToMLMultiArray(hiddenState, hiddenArray)

                // Create cell state array [1, 128]
                val cellArray = createMLMultiArray(listOf(1, VAD_STATE_SIZE), MLMultiArrayDataTypeFloat32)
                    ?: return null
                copyFloatArrayToMLMultiArray(cellState, cellArray)

                // Create input provider
                val inputDict = mapOf<Any?, Any?>(
                    "audio_input" to audioArray,
                    "hidden_state" to hiddenArray,
                    "cell_state" to cellArray
                )
                val errorPtr = alloc<ObjCObjectVar<NSError?>>()
                val inputProvider = MLDictionaryFeatureProvider(inputDict, errorPtr.ptr)
                    ?: return null

                // Run inference
                val output = model.predictionFromFeatures(inputProvider, errorPtr.ptr)
                    ?: return null

                // Extract outputs
                val vadOutput = output.featureValueForName("vad_output")?.multiArrayValue
                    ?: return null
                val newHidden = output.featureValueForName("new_hidden_state")?.multiArrayValue
                    ?: return null
                val newCell = output.featureValueForName("new_cell_state")?.multiArrayValue
                    ?: return null

                val probability = getFloatFromMLMultiArray(vadOutput, 0)
                val newHiddenState = FloatArray(VAD_STATE_SIZE) { getFloatFromMLMultiArray(newHidden, it) }
                val newCellState = FloatArray(VAD_STATE_SIZE) { getFloatFromMLMultiArray(newCell, it) }

                VADOutput(probability, newHiddenState, newCellState)
            } catch (e: Exception) {
                println("VAD inference error: ${e.message}")
                null
            }
        }
    }

    /**
     * Run ASR inference
     * Input: LFR features [1, 500, 560]
     * Output: logits [1, T, vocab_size]
     */
    fun runASR(features: List<FloatArray>): List<FloatArray>? {
        return memScoped {
            try {
                val frames = features.size
                val featureDim = features.firstOrNull()?.size ?: FEATURE_DIM

                // Create input array [1, frames, feature_dim]
                val inputArray = createMLMultiArray(listOf(1, frames, featureDim), MLMultiArrayDataTypeFloat32)
                    ?: return null

                // Copy features - flattened row-major
                var idx = 0
                for (frame in features) {
                    for (value in frame) {
                        setFloatInMLMultiArray(inputArray, idx++, value)
                    }
                }

                // Create input provider
                val inputDict = mapOf<Any?, Any?>("audio_features" to inputArray)
                val errorPtr = alloc<ObjCObjectVar<NSError?>>()
                val inputProvider = MLDictionaryFeatureProvider(inputDict, errorPtr.ptr)
                    ?: return null

                // Run inference
                val output = model.predictionFromFeatures(inputProvider, errorPtr.ptr)
                    ?: return null

                // Extract logits
                val logitsArray = output.featureValueForName("logits")?.multiArrayValue
                    ?: return null

                // Get shape and strides
                val outputShape = logitsArray.shape.map { (it as NSNumber).intValue }
                val strides = logitsArray.strides.map { (it as NSNumber).intValue }

                val time = outputShape[1]
                val vocab = outputShape[2]
                val stride1 = strides[1]
                val stride2 = strides[2]

                // Convert to List<FloatArray>
                val logits = mutableListOf<FloatArray>()
                for (t in 0 until time) {
                    val frame = FloatArray(vocab)
                    for (v in 0 until vocab) {
                        val index = t * stride1 + v * stride2
                        frame[v] = getFloatFromMLMultiArray(logitsArray, index)
                    }
                    logits.add(frame)
                }

                logits
            } catch (e: Exception) {
                println("ASR inference error: ${e.message}")
                null
            }
        }
    }

    /**
     * Run speaker embedding (xvector) inference
     * Input: audio [1, 48000] as Float16
     * Output: embedding [512] as Float32
     */
    fun runSpeakerEmbedding(audio: FloatArray): FloatArray? {
        return memScoped {
            try {
                // Create input array [1, 48000] as Float16
                val inputArray = createMLMultiArray(listOf(1, XVECTOR_SAMPLES), MLMultiArrayDataTypeFloat16)
                    ?: return null

                // Copy audio as Float16
                for (i in audio.indices) {
                    setFloat16InMLMultiArray(inputArray, i, audio[i])
                }

                // Create input provider
                val inputDict = mapOf<Any?, Any?>("audio" to inputArray)
                val errorPtr = alloc<ObjCObjectVar<NSError?>>()
                val inputProvider = MLDictionaryFeatureProvider(inputDict, errorPtr.ptr)
                    ?: return null

                // Run inference
                val output = model.predictionFromFeatures(inputProvider, errorPtr.ptr)
                    ?: return null

                // Extract embedding [1, 1, 512] as Float16
                val embeddingArray = output.featureValueForName("embedding")?.multiArrayValue
                    ?: return null

                val embedding = FloatArray(XVECTOR_DIM) {
                    getFloat16FromMLMultiArray(embeddingArray, it)
                }

                embedding
            } catch (e: Exception) {
                println("Speaker embedding error: ${e.message}")
                null
            }
        }
    }

    /**
     * Get Float32 value from MLMultiArray at flat index
     */
    private fun getFloatFromMLMultiArray(array: MLMultiArray, index: Int): Float {
        val ptr = array.dataPointer ?: return 0f
        return ptr.reinterpret<FloatVar>()[index]
    }

    /**
     * Set Float32 value in MLMultiArray at flat index
     */
    private fun setFloatInMLMultiArray(array: MLMultiArray, index: Int, value: Float) {
        val ptr = array.dataPointer ?: return
        ptr.reinterpret<FloatVar>()[index] = value
    }

    /**
     * Get Float16 value from MLMultiArray at flat index and convert to Float32
     */
    private fun getFloat16FromMLMultiArray(array: MLMultiArray, index: Int): Float {
        val ptr = array.dataPointer ?: return 0f
        val bits = ptr.reinterpret<UShortVar>()[index]
        return float16ToFloat(bits)
    }

    /**
     * Set Float16 value in MLMultiArray at flat index (converting from Float32)
     */
    private fun setFloat16InMLMultiArray(array: MLMultiArray, index: Int, value: Float) {
        val ptr = array.dataPointer ?: return
        ptr.reinterpret<UShortVar>()[index] = floatToFloat16(value)
    }

    /**
     * Copy FloatArray to MLMultiArray (Float32)
     */
    private fun copyFloatArrayToMLMultiArray(src: FloatArray, dst: MLMultiArray) {
        val ptr = dst.dataPointer ?: return
        val floatPtr = ptr.reinterpret<FloatVar>()
        for (i in src.indices) {
            floatPtr[i] = src[i]
        }
    }

    /**
     * Run generic inference with input dictionary
     * @param inputs Map of input name to MLMultiArray
     * @return Map of output name to MLMultiArray
     */
    fun predict(inputs: Map<String, MLMultiArray>): Map<String, MLMultiArray>? {
        return memScoped {
            try {
                val inputDict = inputs.mapKeys { it.key as Any? }.mapValues { it.value as Any? }
                val errorPtr = alloc<ObjCObjectVar<NSError?>>()
                val inputProvider = MLDictionaryFeatureProvider(inputDict, errorPtr.ptr)
                    ?: return null

                val output = model.predictionFromFeatures(inputProvider, errorPtr.ptr)
                    ?: return null

                // Extract all outputs
                val result = mutableMapOf<String, MLMultiArray>()
                val featureNames = output.featureNames
                for (name in featureNames) {
                    val nameStr = name as? String ?: continue
                    val array = output.featureValueForName(nameStr)?.multiArrayValue
                    if (array != null) {
                        result[nameStr] = array
                    }
                }
                result
            } catch (e: Exception) {
                println("Predict error: ${e.message}")
                null
            }
        }
    }
}

/**
 * VAD inference output
 */
data class VADOutput(
    val probability: Float,
    val newHiddenState: FloatArray,
    val newCellState: FloatArray
)

/**
 * Convert Float32 to Float16 (IEEE 754 half-precision)
 */
@OptIn(ExperimentalForeignApi::class)
private fun floatToFloat16(value: Float): UShort {
    val bits = value.toBits()
    val sign = (bits ushr 16) and 0x8000
    val exp = ((bits ushr 23) and 0xFF) - 127 + 15
    val frac = (bits ushr 13) and 0x3FF

    return when {
        exp <= 0 -> sign.toUShort() // Underflow to zero
        exp >= 31 -> (sign or 0x7C00).toUShort() // Overflow to infinity
        else -> (sign or (exp shl 10) or frac).toUShort()
    }
}

/**
 * Convert Float16 to Float32
 */
@OptIn(ExperimentalForeignApi::class)
private fun float16ToFloat(bits: UShort): Float {
    val sign = (bits.toInt() and 0x8000) shl 16
    val exp = (bits.toInt() ushr 10) and 0x1F
    val frac = bits.toInt() and 0x3FF

    return when {
        exp == 0 -> Float.fromBits(sign) // Zero or denormal (treated as zero)
        exp == 31 -> Float.fromBits(sign or 0x7F800000 or (frac shl 13)) // Inf or NaN
        else -> Float.fromBits(sign or ((exp - 15 + 127) shl 23) or (frac shl 13))
    }
}

/**
 * Helper functions for MLMultiArray operations
 */
@OptIn(ExperimentalForeignApi::class)
object MLArrayUtils {
    fun copyFloatArray(src: FloatArray, dst: MLMultiArray) {
        val ptr = dst.dataPointer ?: return
        val floatPtr = ptr.reinterpret<FloatVar>()
        for (i in src.indices) {
            floatPtr[i] = src[i]
        }
    }

    fun getFloat(array: MLMultiArray, index: Int): Float {
        val ptr = array.dataPointer ?: return 0f
        return ptr.reinterpret<FloatVar>()[index]
    }

    fun setFloat(array: MLMultiArray, index: Int, value: Float) {
        val ptr = array.dataPointer ?: return
        ptr.reinterpret<FloatVar>()[index] = value
    }

    fun setInt(array: MLMultiArray, index: Int, value: Int) {
        val ptr = array.dataPointer ?: return
        ptr.reinterpret<IntVar>()[index] = value
    }

    fun getShape(array: MLMultiArray): List<Int> {
        return array.shape.map { (it as NSNumber).intValue }
    }

    fun getStrides(array: MLMultiArray): List<Int> {
        return array.strides.map { (it as NSNumber).intValue }
    }
}

/**
 * Model manager for loading all voice pipeline models
 * Supports multiple ASR backends (SenseVoice, Whisper)
 */
@OptIn(ExperimentalForeignApi::class)
class ModelManager(
    private val modelDir: String,
    private val whisperModelDir: String? = null
) {
    var vadModel: CoreMLModel? = null
        private set
    var speakerModel: CoreMLModel? = null
        private set

    // ASR models
    private var senseVoiceModel: CoreMLModel? = null
    private var whisperModel: WhisperASR? = null

    // Current ASR model selection
    var currentASRType: ASRModelType = ASRModelType.SENSEVOICE
        private set

    /**
     * Get the currently active ASR model
     */
    val asrModel: ASRModel?
        get() = when (currentASRType) {
            ASRModelType.SENSEVOICE -> senseVoiceModel?.let {
                SenseVoiceASR(it)
            }
            ASRModelType.WHISPER_TURBO -> whisperModel
        }

    /**
     * Get the raw SenseVoice CoreML model (for backward compatibility)
     */
    val senseVoiceCoreML: CoreMLModel?
        get() = senseVoiceModel

    fun loadModels() {
        println("\nLoading models...")

        // Load VAD model
        var path = "$modelDir/silero-vad-unified-256ms-v6.0.0.mlmodelc"
        vadModel = CoreMLModel.load(path)
        println("  VAD: ${if (vadModel != null) "OK" else "FAILED"}")

        // Load SenseVoice ASR model
        path = "$modelDir/sensevoice-500-itn.mlmodelc"
        senseVoiceModel = CoreMLModel.load(path)
        println("  SenseVoice ASR: ${if (senseVoiceModel != null) "OK" else "FAILED"}")

        // Load Whisper model if path provided
        if (whisperModelDir != null) {
            println("  Loading Whisper Turbo...")
            whisperModel = WhisperASR.load(whisperModelDir)
            println("  Whisper Turbo: ${if (whisperModel != null) "OK" else "FAILED"}")
        }

        // Load speaker model
        path = "$modelDir/xvector.mlmodelc"
        speakerModel = CoreMLModel.load(path)
        println("  Speaker: ${if (speakerModel != null) "OK" else "FAILED"}")
    }

    /**
     * Switch to a different ASR model
     */
    fun setASRModel(type: ASRModelType): Boolean {
        return when (type) {
            ASRModelType.SENSEVOICE -> {
                if (senseVoiceModel != null) {
                    currentASRType = type
                    println("Switched to SenseVoice ASR")
                    true
                } else {
                    println("SenseVoice model not loaded")
                    false
                }
            }
            ASRModelType.WHISPER_TURBO -> {
                if (whisperModel != null) {
                    currentASRType = type
                    println("Switched to Whisper Turbo ASR")
                    true
                } else {
                    println("Whisper Turbo model not loaded")
                    false
                }
            }
        }
    }

    /**
     * Get list of available ASR models
     */
    fun getAvailableASRModels(): List<ASRModelType> {
        val available = mutableListOf<ASRModelType>()
        if (senseVoiceModel != null) available.add(ASRModelType.SENSEVOICE)
        if (whisperModel != null) available.add(ASRModelType.WHISPER_TURBO)
        return available
    }
}
