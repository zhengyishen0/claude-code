package com.voice.platform

import com.voice.core.*

import kotlinx.cinterop.*
import platform.AVFAudio.*
import platform.AVFoundation.*
import platform.AudioToolbox.*
import platform.CoreAudioTypes.*
import platform.Foundation.*
import platform.darwin.dispatch_async
import platform.darwin.dispatch_get_main_queue

/**
 * Audio capture using AVAudioEngine for macOS
 * Provides callback-based audio streaming at 16kHz mono
 */
@OptIn(ExperimentalForeignApi::class)
class AudioCapture {
    private var audioEngine: AVAudioEngine? = null
    private var audioCallback: ((FloatArray) -> Unit)? = null
    private var isRunning = false

    /**
     * Start capturing audio from the default input device
     * @param callback Called with audio samples at 16kHz mono
     */
    fun start(callback: (FloatArray) -> Unit) {
        if (isRunning) {
            println("AudioCapture already running")
            return
        }

        audioCallback = callback
        audioEngine = AVAudioEngine()

        val engine = audioEngine ?: return
        val inputNode = engine.inputNode

        // Get native format
        val nativeFormat = inputNode.inputFormatForBus(0u)
        val nativeSampleRate = nativeFormat.sampleRate
        val nativeChannels = nativeFormat.channelCount

        println("Native audio format: ${nativeSampleRate}Hz, $nativeChannels channels")

        // Create target format (16kHz mono)
        val targetFormat = AVAudioFormat(
            standardFormatWithSampleRate = SAMPLE_RATE.toDouble(),
            channels = 1u
        )

        // Create converter if sample rate differs
        val converter = if (nativeSampleRate != SAMPLE_RATE.toDouble()) {
            AVAudioConverter(nativeFormat, targetFormat!!)
        } else {
            null
        }

        // Calculate buffer size for ~256ms chunks
        val bufferSize = (nativeSampleRate * 0.256).toUInt()

        // Install tap on input node
        inputNode.installTapOnBus(
            bus = 0u,
            bufferSize = bufferSize,
            format = nativeFormat
        ) { buffer, _ ->
            buffer?.let { audioBuffer ->
                processAudioBuffer(audioBuffer, converter, targetFormat)
            }
        }

        // Start engine
        memScoped {
            val errorPtr = alloc<ObjCObjectVar<NSError?>>()
            engine.prepare()

            if (!engine.startAndReturnError(errorPtr.ptr)) {
                println("Failed to start audio engine: ${errorPtr.value?.localizedDescription}")
                return
            }
        }

        isRunning = true
        println("Audio capture started at ${nativeSampleRate}Hz (resampling to ${SAMPLE_RATE}Hz)")
    }

    /**
     * Stop capturing audio
     */
    fun stop() {
        if (!isRunning) return

        audioEngine?.inputNode?.removeTapOnBus(0u)
        audioEngine?.stop()
        audioEngine = null
        audioCallback = null
        isRunning = false

        println("Audio capture stopped")
    }

    /**
     * Process audio buffer and call callback with resampled audio
     */
    private fun processAudioBuffer(
        buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter?,
        targetFormat: AVAudioFormat?
    ) {
        val callback = audioCallback ?: return

        val floatData = buffer.floatChannelData
        if (floatData == null) {
            println("No float data in buffer")
            return
        }

        val frameCount = buffer.frameLength.toInt()
        val channelCount = buffer.format.channelCount.toInt()

        // Extract first channel (mono)
        val channelPtr = floatData[0] ?: return
        val samples = FloatArray(frameCount) { channelPtr[it] }

        // Resample if needed
        val finalSamples = if (converter != null && targetFormat != null) {
            resampleAudio(samples, buffer.format.sampleRate.toInt(), SAMPLE_RATE)
        } else {
            samples
        }

        callback(finalSamples)
    }

    /**
     * Simple linear interpolation resampling
     */
    private fun resampleAudio(input: FloatArray, sourceSR: Int, targetSR: Int): FloatArray {
        if (sourceSR == targetSR) return input

        val ratio = targetSR.toDouble() / sourceSR
        val outputLength = (input.size * ratio).toInt()
        val output = FloatArray(outputLength)

        for (i in 0 until outputLength) {
            val srcIndex = i / ratio
            val srcIndexInt = srcIndex.toInt()
            val frac = (srcIndex - srcIndexInt).toFloat()

            output[i] = if (srcIndexInt + 1 < input.size) {
                input[srcIndexInt] * (1 - frac) + input[srcIndexInt + 1] * frac
            } else if (srcIndexInt < input.size) {
                input[srcIndexInt]
            } else {
                0f
            }
        }

        return output
    }

    /**
     * Check if microphone permission is granted
     */
    fun checkPermission(): Boolean {
        val status = AVCaptureDevice.authorizationStatusForMediaType(AVMediaTypeAudio)
        return status == AVAuthorizationStatusAuthorized
    }

    /**
     * Request microphone permission
     */
    fun requestPermission(callback: (Boolean) -> Unit) {
        AVCaptureDevice.requestAccessForMediaType(AVMediaTypeAudio) { granted ->
            dispatch_async(dispatch_get_main_queue()) {
                callback(granted)
            }
        }
    }
}

/**
 * Simple audio file reader for testing
 */
@OptIn(ExperimentalForeignApi::class)
object AudioFileReader {
    /**
     * Read audio file and return samples as FloatArray
     * Automatically converts to 16kHz mono
     */
    fun readFile(path: String): FloatArray? {
        val url = NSURL.fileURLWithPath(path)

        return memScoped {
            val errorPtr = alloc<ObjCObjectVar<NSError?>>()
            val file = AVAudioFile(url, errorPtr.ptr)

            if (file == null) {
                println("Failed to open audio file: ${errorPtr.value?.localizedDescription}")
                return null
            }

            val format = file.processingFormat
            val frameCount = file.length.toUInt()

            // Create buffer
            val buffer = AVAudioPCMBuffer(format, frameCount) ?: return null

            // Read file
            if (!file.readIntoBuffer(buffer, errorPtr.ptr)) {
                println("Failed to read audio file: ${errorPtr.value?.localizedDescription}")
                return null
            }

            // Extract samples
            val floatData = buffer.floatChannelData ?: return null
            val channelPtr = floatData[0] ?: return null

            val samples = FloatArray(frameCount.toInt()) { channelPtr[it] }

            // Resample if needed
            val sourceSR = format.sampleRate.toInt()
            if (sourceSR != SAMPLE_RATE) {
                AudioProcessing.resample(samples, sourceSR, SAMPLE_RATE)
            } else {
                samples
            }
        }
    }
}
