package com.voice.cli

import com.voice.core.*
import com.voice.platform.*

import kotlin.math.sqrt

/**
 * Live voice pipeline integrating:
 * - VAD (Voice Activity Detection)
 * - ASR (Automatic Speech Recognition)
 * - Speaker identification
 *
 * Supports multiple ASR backends (SenseVoice, Whisper Turbo)
 */
class LivePipeline(
    private val vadModel: CoreMLModel,
    private val asrModel: ASRModel,
    private val speakerModel: CoreMLModel,
    private val onResult: (TranscriptionResult) -> Unit
) {
    // VAD state
    private var vadHidden = FloatArray(VAD_STATE_SIZE) { 0f }
    private var vadCell = FloatArray(VAD_STATE_SIZE) { 0f }
    private var vadContext = FloatArray(VAD_CONTEXT_SIZE) { 0f }

    // Audio buffer for accumulating chunks
    private val audioBuffer = mutableListOf<Float>()

    // Speech detection state
    private var isSpeaking = false
    private var speechBuffer = mutableListOf<Float>()
    private var silenceFrames = 0
    private var speechFrames = 0

    // Speaker library (in-memory for now)
    private val voiceLibrary = VoiceLibrary("")

    // Timing thresholds (in VAD frames)
    private val minSpeechFrames = (MIN_SPEECH_DURATION * SAMPLE_RATE / VAD_CHUNK_SIZE).toInt()
    private val minSilenceFrames = (MIN_SILENCE_DURATION * SAMPLE_RATE / VAD_CHUNK_SIZE).toInt()

    /**
     * Process incoming audio chunk
     */
    fun processAudio(samples: FloatArray) {
        // Add samples to buffer
        for (s in samples) {
            audioBuffer.add(s)
        }

        // Process VAD chunks
        while (audioBuffer.size >= VAD_CHUNK_SIZE) {
            val chunk = FloatArray(VAD_CHUNK_SIZE) { audioBuffer[it] }
            audioBuffer.subList(0, VAD_CHUNK_SIZE).clear()

            processVADChunk(chunk)
        }
    }

    /**
     * Process a single VAD chunk
     */
    private fun processVADChunk(chunk: FloatArray) {
        // Prepare VAD input: context (64) + chunk (4096) = 4160 samples
        val vadInput = FloatArray(VAD_MODEL_INPUT_SIZE)
        for (i in 0 until VAD_CONTEXT_SIZE) {
            vadInput[i] = vadContext[i]
        }
        for (i in 0 until VAD_CHUNK_SIZE) {
            vadInput[VAD_CONTEXT_SIZE + i] = chunk[i]
        }

        // Update context for next chunk
        for (i in 0 until VAD_CONTEXT_SIZE) {
            vadContext[i] = chunk[VAD_CHUNK_SIZE - VAD_CONTEXT_SIZE + i]
        }

        // Run VAD inference
        val vadOutput = vadModel.runVAD(vadInput, vadHidden, vadCell) ?: return

        vadHidden = vadOutput.newHiddenState
        vadCell = vadOutput.newCellState

        val probability = vadOutput.probability
        val isSpeech = probability >= VAD_SPEECH_THRESHOLD

        // State machine for speech detection
        if (isSpeech) {
            speechFrames++
            silenceFrames = 0

            // Add chunk to speech buffer
            for (s in chunk) {
                speechBuffer.add(s)
            }

            // Start speaking if enough consecutive speech
            if (!isSpeaking && speechFrames >= minSpeechFrames) {
                isSpeaking = true
            }
        } else {
            silenceFrames++
            speechFrames = 0

            if (isSpeaking) {
                // Still add some trailing audio
                if (silenceFrames <= minSilenceFrames) {
                    for (s in chunk) {
                        speechBuffer.add(s)
                    }
                }

                // End speech if enough silence
                if (silenceFrames >= minSilenceFrames) {
                    processCompletedSpeech()
                    isSpeaking = false
                }
            } else {
                // Not speaking, clear buffer
                speechBuffer.clear()
            }
        }
    }

    /**
     * Process completed speech segment
     */
    private fun processCompletedSpeech() {
        if (speechBuffer.isEmpty()) return

        val audio = speechBuffer.toFloatArray()
        speechBuffer.clear()

        // Check minimum length
        if (audio.size < SAMPLE_RATE * MIN_SPEECH_DURATION) {
            return
        }

        // Run ASR inference using the ASRModel interface
        val asrResult = asrModel.transcribe(audio) ?: return

        val text = asrResult.text
        val textTokens = asrResult.tokens
        val language = asrResult.language ?: "unknown"

        // Speaker identification
        var speakerId = "Unknown"
        if (audio.size >= XVECTOR_SAMPLES) {
            // Take center portion for embedding
            val start = (audio.size - XVECTOR_SAMPLES) / 2
            val xvectorInput = FloatArray(XVECTOR_SAMPLES) { audio[start + it] }

            val embedding = speakerModel.runSpeakerEmbedding(xvectorInput)
            if (embedding != null) {
                val (matchedName, score, confidence) = voiceLibrary.match(embedding)

                if (matchedName != null) {
                    speakerId = matchedName

                    // Auto-learn if high confidence
                    if (confidence == "high") {
                        voiceLibrary.autoLearn(matchedName, embedding, score)
                    }
                } else {
                    // New speaker - auto-enroll
                    speakerId = "Speaker_${voiceLibrary.getSpeakerNames().size + 1}"
                    voiceLibrary.enrollSpeaker(speakerId, embedding)
                }
            }
        }

        // Create result
        val result = TranscriptionResult(
            text = text,
            tokens = textTokens,
            speakerId = speakerId,
            language = language,
            emotion = "unknown",  // Whisper doesn't provide emotion
            duration = audio.size.toFloat() / SAMPLE_RATE,
            modelType = asrModel.modelType
        )

        onResult(result)
    }

    /**
     * Reset pipeline state
     */
    fun reset() {
        vadHidden = FloatArray(VAD_STATE_SIZE) { 0f }
        vadCell = FloatArray(VAD_STATE_SIZE) { 0f }
        vadContext = FloatArray(VAD_CONTEXT_SIZE) { 0f }
        audioBuffer.clear()
        speechBuffer.clear()
        isSpeaking = false
        silenceFrames = 0
        speechFrames = 0
    }

    /**
     * Flush any remaining speech
     */
    fun flush() {
        if (isSpeaking && speechBuffer.isNotEmpty()) {
            processCompletedSpeech()
        }
        reset()
    }
}

/**
 * Transcription result from the pipeline
 */
data class TranscriptionResult(
    val text: String,
    val tokens: List<Int>,
    val speakerId: String,
    val language: String,
    val emotion: String,
    val duration: Float,
    val modelType: ASRModelType = ASRModelType.SENSEVOICE
)

/**
 * Simple file-based pipeline for testing
 */
object FilePipeline {
    /**
     * Process an audio file and return transcription results
     */
    fun processFile(
        audioPath: String,
        vadModel: CoreMLModel,
        asrModel: ASRModel,
        speakerModel: CoreMLModel
    ): List<TranscriptionResult> {
        val results = mutableListOf<TranscriptionResult>()

        val pipeline = LivePipeline(vadModel, asrModel, speakerModel) { result ->
            results.add(result)
        }

        // Read audio file
        val audio = AudioFileReader.readFile(audioPath)
        if (audio == null) {
            println("Failed to read audio file: $audioPath")
            return results
        }

        println("Processing ${audio.size} samples (${audio.size.toFloat() / SAMPLE_RATE}s)")

        // Process in chunks
        val chunkSize = VAD_CHUNK_SIZE
        var offset = 0
        while (offset < audio.size) {
            val end = minOf(offset + chunkSize, audio.size)
            val chunk = audio.copyOfRange(offset, end)

            // Pad if needed
            val paddedChunk = if (chunk.size < chunkSize) {
                FloatArray(chunkSize) { if (it < chunk.size) chunk[it] else 0f }
            } else {
                chunk
            }

            pipeline.processAudio(paddedChunk)
            offset = end
        }

        pipeline.flush()

        return results
    }
}
