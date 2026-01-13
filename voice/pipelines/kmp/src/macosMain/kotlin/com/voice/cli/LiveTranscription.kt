package com.voice.cli

import com.voice.core.*
import com.voice.platform.*

import kotlinx.cinterop.*
import platform.Foundation.*
import platform.darwin.*
import platform.posix.*
import kotlin.math.pow
import kotlin.math.round
import kotlin.math.sqrt
import kotlin.system.getTimeMillis

// Helper for formatting doubles with specified decimal places
private fun Double.format(decimals: Int): String {
    return when (decimals) {
        0 -> round(this).toLong().toString()
        1 -> {
            val r = round(this * 10) / 10
            val str = r.toString()
            // Ensure at least one decimal
            if (!str.contains('.')) "$str.0" else str
        }
        else -> {
            val factor = 10.0.pow(decimals)
            val r = round(this * factor) / factor
            r.toString()
        }
    }
}

/**
 * Segment data for post-processing
 */
data class Segment(
    val startTime: Double,
    val endTime: Double,
    val text: String,
    val speakerName: String?,
    val confidence: String,
    val isKnown: Boolean,
    val isConflict: Boolean,
    val embedding: FloatArray?,
    val processTimeMs: Long,
    val learned: Boolean,
    var clusterLabel: String? = null
)

/**
 * Live transcription session with speaker identification
 * Supports multiple ASR backends (SenseVoice, Whisper Turbo)
 */
class LiveTranscription(
    private val vadModel: CoreMLModel,
    private val asrModel: ASRModel,
    private val speakerModel: CoreMLModel,
    private val voiceLibraryPath: String = ""
) {
    // Voice library for speaker identification
    private val voiceLibrary = VoiceLibrary(voiceLibraryPath)

    // All segments from this session
    private val segments = mutableListOf<Segment>()

    // VAD state
    private var vadHidden = FloatArray(VAD_STATE_SIZE) { 0f }
    private var vadCell = FloatArray(VAD_STATE_SIZE) { 0f }
    private var vadContext = FloatArray(VAD_CONTEXT_SIZE) { 0f }

    // Audio buffer
    private val audioBuffer = mutableListOf<Float>()
    private val speechBuffer = mutableListOf<Float>()

    // Speech detection state
    private var isSpeaking = false
    private var silenceFrames = 0
    private var speechFrames = 0
    private var speechStartSample = 0L
    private var totalSamplesProcessed = 0L

    // Timing thresholds
    private val minSpeechFrames = (MIN_SPEECH_DURATION * SAMPLE_RATE / VAD_CHUNK_SIZE).toInt()
    private val minSilenceFrames = (MIN_SILENCE_DURATION * SAMPLE_RATE / VAD_CHUNK_SIZE).toInt()

    // Running state
    private var isRunning = false

    /**
     * Process audio samples
     */
    fun processAudio(samples: FloatArray) {
        for (s in samples) {
            audioBuffer.add(s)
        }

        while (audioBuffer.size >= VAD_CHUNK_SIZE) {
            val chunk = FloatArray(VAD_CHUNK_SIZE) { audioBuffer[it] }
            audioBuffer.subList(0, VAD_CHUNK_SIZE).clear()
            processVADChunk(chunk)
        }
    }

    private fun processVADChunk(chunk: FloatArray) {
        // Prepare VAD input
        val vadInput = FloatArray(VAD_MODEL_INPUT_SIZE)
        for (i in 0 until VAD_CONTEXT_SIZE) {
            vadInput[i] = vadContext[i]
        }
        for (i in 0 until VAD_CHUNK_SIZE) {
            vadInput[VAD_CONTEXT_SIZE + i] = chunk[i]
        }

        // Update context
        for (i in 0 until VAD_CONTEXT_SIZE) {
            vadContext[i] = chunk[VAD_CHUNK_SIZE - VAD_CONTEXT_SIZE + i]
        }

        val vadOutput = vadModel.runVAD(vadInput, vadHidden, vadCell) ?: return
        vadHidden = vadOutput.newHiddenState
        vadCell = vadOutput.newCellState

        val isSpeech = vadOutput.probability >= VAD_SPEECH_THRESHOLD

        if (isSpeech) {
            speechFrames++
            silenceFrames = 0

            for (s in chunk) {
                speechBuffer.add(s)
            }

            if (!isSpeaking && speechFrames >= minSpeechFrames) {
                isSpeaking = true
                speechStartSample = totalSamplesProcessed - (speechFrames * VAD_CHUNK_SIZE)
            }
        } else {
            silenceFrames++
            speechFrames = 0

            if (isSpeaking) {
                if (silenceFrames <= minSilenceFrames) {
                    for (s in chunk) {
                        speechBuffer.add(s)
                    }
                }

                if (silenceFrames >= minSilenceFrames) {
                    val speechEndSample = totalSamplesProcessed
                    processCompletedSpeech(speechStartSample, speechEndSample)
                    isSpeaking = false
                }
            } else {
                speechBuffer.clear()
            }
        }

        totalSamplesProcessed += VAD_CHUNK_SIZE
    }

    private fun processCompletedSpeech(startSample: Long, endSample: Long) {
        if (speechBuffer.isEmpty()) return

        val processStart = getTimeMillis()
        val audio = speechBuffer.toFloatArray()
        speechBuffer.clear()

        if (audio.size < SAMPLE_RATE * MIN_SPEECH_DURATION) {
            return
        }

        val startTime = startSample.toDouble() / SAMPLE_RATE
        val endTime = endSample.toDouble() / SAMPLE_RATE

        // ASR - use the ASRModel interface (works with both SenseVoice and Whisper)
        val asrResult = asrModel.transcribe(audio) ?: return
        val text = asrResult.text
        val textTokens = asrResult.tokens

        // Speaker identification
        var speakerName: String? = null
        var confidence = "unknown"
        var isKnown = false
        var isConflict = false
        var embedding: FloatArray? = null
        var learned = false

        if (audio.size >= XVECTOR_SAMPLES) {
            val center = (audio.size - XVECTOR_SAMPLES) / 2
            val xvectorInput = audio.copyOfRange(center, center + XVECTOR_SAMPLES)
            embedding = speakerModel.runSpeakerEmbedding(xvectorInput)

            if (embedding != null) {
                val (matchedName, score, matchConfidence) = voiceLibrary.match(embedding)
                confidence = matchConfidence

                if (matchedName != null) {
                    speakerName = matchedName
                    isKnown = true

                    // Check for conflict (name contains "/")
                    if (matchedName.contains("/")) {
                        isConflict = true
                    }

                    // Auto-learn if high confidence
                    if (matchConfidence == "high") {
                        learned = voiceLibrary.autoLearn(matchedName, embedding, score)
                    }
                }
            }
        }

        val processTime = getTimeMillis() - processStart

        // Create segment
        val segment = Segment(
            startTime = startTime,
            endTime = endTime,
            text = text,
            speakerName = speakerName,
            confidence = confidence,
            isKnown = isKnown,
            isConflict = isConflict,
            embedding = embedding,
            processTimeMs = processTime,
            learned = learned
        )
        segments.add(segment)

        // Print live output in Python/Swift format
        printLiveOutput(segment)
    }

    /**
     * Check if segment is noise (EMO_UNKNOWN only, very short, etc.)
     */
    private fun isNoiseSegment(segment: Segment): Boolean {
        val text = segment.text.trim()
        // Pure EMO_UNKNOWN or very short meaningless text
        return text.startsWith("<|EMO_UNKNOWN|>") &&
               text.replace("<|EMO_UNKNOWN|>", "").trim().length < 3
    }

    /**
     * Print output in format: [Speaker] (start-end) text [msec]
     */
    private fun printLiveOutput(segment: Segment) {
        // Skip noise segments
        if (isNoiseSegment(segment)) {
            return
        }

        val speakerLabel = when {
            segment.isConflict -> segment.speakerName ?: "???"
            segment.isKnown && segment.confidence == "high" -> segment.speakerName ?: "???"
            segment.isKnown -> "${segment.speakerName}?"
            else -> "???"
        }

        val learnIndicator = if (segment.learned) " \uD83D\uDCDA" else ""

        // Clean up EMO_UNKNOWN from display text
        val displayText = segment.text.replace("<|EMO_UNKNOWN|>", "").trim()

        val startStr = segment.startTime.format(1)
        val endStr = segment.endTime.format(1)
        println("[${speakerLabel}] (${startStr}s-${endStr}s) $displayText  [${segment.processTimeMs}ms]$learnIndicator")
    }

    /**
     * Cluster unknown speakers using simple distance-based clustering
     */
    fun clusterUnknowns(): Int {
        // Filter: unknown, has embedding, not just noise
        val unknowns = segments.filter {
            !it.isKnown &&
            !it.isConflict &&
            it.embedding != null &&
            !it.text.trim().startsWith("<|EMO_UNKNOWN|>") // Filter pure noise
        }

        // Set labels for known speakers first
        for (segment in segments) {
            if (segment.isKnown) {
                segment.clusterLabel = segment.speakerName
            } else if (segment.isConflict) {
                segment.clusterLabel = segment.speakerName
            }
        }

        // Mark segments without embeddings as "Short" (can't identify)
        for (segment in segments) {
            if (!segment.isKnown && !segment.isConflict && segment.embedding == null) {
                segment.clusterLabel = "Short"
            }
        }

        if (unknowns.isEmpty()) {
            println("  (No unknown segments with speaker embeddings to cluster)")
            return 0
        }

        if (unknowns.size == 1) {
            unknowns[0].clusterLabel = "Speaker A"
            return 1
        }

        // Simple agglomerative clustering using cosine distance
        val embeddings = unknowns.map { it.embedding!! }
        val n = embeddings.size

        // Initialize each point as its own cluster
        val clusterAssignment = IntArray(n) { it }
        val distanceThreshold = 0.5f // cosine distance threshold

        // Compute pairwise distances and merge
        for (i in 0 until n) {
            for (j in i + 1 until n) {
                val similarity = cosineSimilarity(embeddings[i], embeddings[j])
                val distance = 1 - similarity

                if (distance < distanceThreshold) {
                    // Merge clusters
                    val oldCluster = clusterAssignment[j]
                    val newCluster = clusterAssignment[i]
                    for (k in 0 until n) {
                        if (clusterAssignment[k] == oldCluster) {
                            clusterAssignment[k] = newCluster
                        }
                    }
                }
            }
        }

        // Renumber clusters to be contiguous
        val uniqueClusters = clusterAssignment.toSet().sorted()
        val clusterMap = uniqueClusters.withIndex().associate { it.value to it.index }

        // Assign labels
        for ((idx, segment) in unknowns.withIndex()) {
            val clusterId = clusterMap[clusterAssignment[idx]] ?: 0
            segment.clusterLabel = "Speaker ${('A' + clusterId)}"
        }

        return uniqueClusters.size
    }

    /**
     * Show transcript with clustering
     */
    fun showTranscript() {
        println()
        println("=".repeat(60))
        println("TRANSCRIPT (with clustering)")
        println("=".repeat(60))
        println()

        val nonNoiseSegments = segments.filter { !isNoiseSegment(it) }
        val noiseCount = segments.size - nonNoiseSegments.size

        for (segment in nonNoiseSegments) {
            val label = segment.clusterLabel ?: segment.speakerName ?: "???"
            val displayText = segment.text.replace("<|EMO_UNKNOWN|>", "").trim()
            val st = segment.startTime.format(1)
            val et = segment.endTime.format(1)
            println("[$label] (${st}s-${et}s) $displayText")
        }

        if (noiseCount > 0) {
            println("\n  ($noiseCount noise segments filtered)")
        }
    }

    /**
     * Show statistics
     */
    fun showStats() {
        println()
        println("-".repeat(60))
        println("STATISTICS")
        println("-".repeat(60))

        // Filter out noise
        val validSegments = segments.filter { !isNoiseSegment(it) }
        val noiseCount = segments.size - validSegments.size

        val totalSegments = validSegments.size
        val knownCount = validSegments.count { it.isKnown }
        val unknownCount = validSegments.count { !it.isKnown && !it.isConflict }
        val conflictCount = validSegments.count { it.isConflict }
        val learnedCount = validSegments.count { it.learned }

        val avgProcessTime = if (validSegments.isNotEmpty()) {
            validSegments.map { it.processTimeMs }.average()
        } else 0.0

        val totalDuration = validSegments.sumOf { it.endTime - it.startTime }

        println("  Total segments: $totalSegments" + if (noiseCount > 0) " (+$noiseCount noise filtered)" else "")
        println("  Known speakers: $knownCount")
        println("  Unknown speakers: $unknownCount")
        println("  Conflicts: $conflictCount")
        println("  Auto-learned: $learnedCount")
        println("  Avg process time: ${avgProcessTime.format(0)}ms")
        println("  Total speech duration: ${totalDuration.format(1)}s")
    }

    /**
     * Confirm outliers (medium-confidence matches) to expand boundary layer
     * These are segments where we recognized the speaker but with less certainty
     */
    fun confirmOutliers() {
        // Find medium-confidence matches (recognized but not high confidence)
        val outliers = segments.filter {
            it.isKnown && it.confidence == "medium" && it.embedding != null && !it.isConflict
        }.groupBy { it.speakerName }

        if (outliers.isEmpty()) {
            return
        }

        println()
        println("-".repeat(60))
        println("CONFIRM BOUNDARY EXPANSIONS")
        println("-".repeat(60))
        println("These segments were recognized with medium confidence.")
        println("Confirm to expand the speaker's voice boundary.")
        println()

        var confirmed = 0
        for ((speaker, segs) in outliers) {
            if (speaker == null) continue

            val sampleTexts = segs.take(2).joinToString(" | ") {
                it.text.take(40) + if (it.text.length > 40) "..." else ""
            }

            println("[$speaker?] (${segs.size} segments):")
            println("  Sample: $sampleTexts")
            print("  Confirm as $speaker? [Y/n]: ")

            val input = readlnOrNull()?.trim()?.lowercase()

            if (input.isNullOrEmpty() || input == "y" || input == "yes") {
                // Add embeddings to boundary layer
                val embeddings = segs.mapNotNull { it.embedding }
                for (emb in embeddings) {
                    voiceLibrary.addEmbedding(speaker, emb, forceBoundary = true)
                }
                confirmed += embeddings.size
                println("  -> Added ${embeddings.size} embeddings to boundary")
            } else {
                println("  -> Skipped")
            }
            println()
        }

        if (confirmed > 0) {
            println("Added $confirmed embeddings to speaker boundaries.")
        }
    }

    /**
     * Prompt user to name unknown speaker clusters
     */
    fun promptNaming() {
        // Get clusters with actual speaker embeddings
        val clusters = segments
            .filter { it.clusterLabel?.startsWith("Speaker ") == true && it.embedding != null }
            .groupBy { it.clusterLabel }

        // Count short segments (no embedding)
        val shortSegments = segments.count { it.clusterLabel == "Short" }

        if (clusters.isEmpty()) {
            if (shortSegments > 0) {
                println("\n  ($shortSegments segments too short for speaker identification)")
            }
            return
        }

        println()
        println("-".repeat(60))
        println("NAME NEW SPEAKERS")
        println("-".repeat(60))
        println("These are new voices not in your library.")
        println("Enter a name to remember them, or press Enter to skip.")
        println()

        for ((label, segs) in clusters.entries.sortedByDescending { it.value.size }) {
            val sampleTexts = segs.take(3).joinToString(" | ") {
                val text = it.text.replace("<|EMO_UNKNOWN|>", "").trim()
                text.take(30) + if (text.length > 30) "..." else ""
            }
            println("$label (${segs.size} segments):")
            println("  Sample: $sampleTexts")
            print("  Name (or Enter to skip): ")

            val input = readlnOrNull()?.trim()

            if (!input.isNullOrEmpty()) {
                // Enroll this speaker with all their embeddings
                val embeddings = segs.mapNotNull { it.embedding }
                if (embeddings.isNotEmpty()) {
                    // Use first embedding to enroll
                    voiceLibrary.enrollSpeaker(input, embeddings.first())

                    // Add remaining embeddings to boundary
                    for (emb in embeddings.drop(1)) {
                        voiceLibrary.addEmbedding(input, emb, forceBoundary = false)
                    }

                    // Update cluster labels
                    for (seg in segs) {
                        seg.clusterLabel = input
                    }

                    println("  -> Enrolled '$input' with ${embeddings.size} embeddings")
                }
            } else {
                println("  -> Skipped")
            }
            println()
        }

        if (shortSegments > 0) {
            println("  ($shortSegments segments too short for speaker identification)")
        }
    }

    /**
     * Save voice library after all confirmations
     */
    fun saveLibrary() {
        if (voiceLibraryPath.isNotEmpty()) {
            voiceLibrary.save()
            println("\nVoice library saved.")
        }
    }

    /**
     * Get all segments
     */
    fun getSegments(): List<Segment> = segments.toList()

    /**
     * Flush remaining audio
     */
    fun flush() {
        if (isSpeaking && speechBuffer.isNotEmpty()) {
            val speechEndSample = totalSamplesProcessed
            processCompletedSpeech(speechStartSample, speechEndSample)
        }
        reset()
    }

    /**
     * Reset state
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
}

// Global flag for signal handling (internal for ONNX live transcription)
internal var globalShouldStop = false

/**
 * Set terminal to raw mode for single keypress detection
 * Returns the original termios settings to restore later
 */
@OptIn(ExperimentalForeignApi::class)
internal fun setRawMode(): termios {
    memScoped {
        val originalTermios = alloc<termios>()
        val rawTermios = alloc<termios>()

        // Get current terminal settings
        tcgetattr(STDIN_FILENO, originalTermios.ptr)

        // Copy to raw settings
        rawTermios.c_iflag = originalTermios.c_iflag
        rawTermios.c_oflag = originalTermios.c_oflag
        rawTermios.c_cflag = originalTermios.c_cflag
        rawTermios.c_lflag = originalTermios.c_lflag

        // Disable canonical mode and echo
        rawTermios.c_lflag = rawTermios.c_lflag and (ICANON or ECHO).toULong().inv().toULong()

        // Set minimum characters and timeout for non-blocking read
        rawTermios.c_cc[VMIN] = 0u  // Don't wait for characters
        rawTermios.c_cc[VTIME] = 0u // No timeout

        // Apply raw settings
        tcsetattr(STDIN_FILENO, TCSANOW, rawTermios.ptr)

        // Return a copy of original settings
        val result = nativeHeap.alloc<termios>()
        result.c_iflag = originalTermios.c_iflag
        result.c_oflag = originalTermios.c_oflag
        result.c_cflag = originalTermios.c_cflag
        result.c_lflag = originalTermios.c_lflag
        for (i in 0 until NCCS) {
            result.c_cc[i] = originalTermios.c_cc[i]
        }
        return result
    }
}

/**
 * Restore terminal settings
 */
@OptIn(ExperimentalForeignApi::class)
internal fun restoreTerminal(originalTermios: termios) {
    memScoped {
        val termiosPtr = alloc<termios>()
        termiosPtr.c_iflag = originalTermios.c_iflag
        termiosPtr.c_oflag = originalTermios.c_oflag
        termiosPtr.c_cflag = originalTermios.c_cflag
        termiosPtr.c_lflag = originalTermios.c_lflag
        for (i in 0 until NCCS) {
            termiosPtr.c_cc[i] = originalTermios.c_cc[i]
        }
        tcsetattr(STDIN_FILENO, TCSANOW, termiosPtr.ptr)
    }
    nativeHeap.free(originalTermios)
}

/**
 * Check if Escape key was pressed (non-blocking)
 */
@OptIn(ExperimentalForeignApi::class)
internal fun checkEscapeKey(): Boolean {
    memScoped {
        val buffer = alloc<IntVar>()
        buffer.value = 0
        val bytesRead = read(STDIN_FILENO, buffer.ptr, 1u)
        if (bytesRead > 0) {
            return (buffer.value and 0xFF) == 27 // Escape key ASCII code
        }
        return false
    }
}

/**
 * Run live transcription from microphone
 * Supports multiple ASR backends (SenseVoice, Whisper Turbo)
 */
@OptIn(ExperimentalForeignApi::class)
fun runLiveTranscription(
    vadModel: CoreMLModel,
    asrModel: ASRModel,
    speakerModel: CoreMLModel,
    voiceLibraryPath: String = ""
) {
    val transcription = LiveTranscription(vadModel, asrModel, speakerModel, voiceLibraryPath)

    println()
    println("=".repeat(60))
    println("LIVE TRANSCRIPTION")
    println("Press ESC to stop")
    println("=".repeat(60))
    println()

    // Set up audio capture
    val audioCapture = AudioCapture()

    globalShouldStop = false

    // Set terminal to raw mode to detect Escape key
    val originalTermios = setRawMode()

    // Start audio capture
    audioCapture.start { samples ->
        if (!globalShouldStop) {
            transcription.processAudio(samples)
        }
    }

    // Main loop - wait for Escape key
    while (!globalShouldStop) {
        if (checkEscapeKey()) {
            globalShouldStop = true
        }
        usleep(50000u) // 50ms - check more frequently for responsive ESC
    }

    // Restore terminal before any output
    restoreTerminal(originalTermios)

    println("\n\nStopping...")

    // Stop capture and flush
    audioCapture.stop()
    transcription.flush()

    // Post-processing
    if (transcription.getSegments().isNotEmpty()) {
        transcription.showStats()

        val nClusters = transcription.clusterUnknowns()
        if (nClusters > 0) {
            println("\n\uD83D\uDCCA Clustered unknowns into $nClusters speaker(s)")
        }

        // Self-improvement flow:
        // 1. Confirm medium-confidence matches to expand boundaries
        transcription.confirmOutliers()

        // 2. Name new speakers from clustered unknowns
        transcription.promptNaming()

        // 3. Save voice library
        transcription.saveLibrary()
    } else {
        println("\nNo speech detected.")
    }
}

/**
 * Process audio file with transcription
 * Supports multiple ASR backends (SenseVoice, Whisper Turbo)
 */
fun processFileTranscription(
    audioPath: String,
    vadModel: CoreMLModel,
    asrModel: ASRModel,
    speakerModel: CoreMLModel,
    voiceLibraryPath: String = ""
): List<Segment> {
    val transcription = LiveTranscription(vadModel, asrModel, speakerModel, voiceLibraryPath)

    val audio = AudioFileReader.readFile(audioPath)
    if (audio == null) {
        println("Failed to read audio file: $audioPath")
        return emptyList()
    }

    val durationStr = (audio.size.toFloat() / SAMPLE_RATE).toDouble().format(1)
    println("Processing ${audio.size} samples (${durationStr}s)")
    println()

    // Process in chunks
    var offset = 0
    while (offset < audio.size) {
        val end = minOf(offset + VAD_CHUNK_SIZE, audio.size)
        val chunk = audio.copyOfRange(offset, end)

        val paddedChunk = if (chunk.size < VAD_CHUNK_SIZE) {
            FloatArray(VAD_CHUNK_SIZE) { if (it < chunk.size) chunk[it] else 0f }
        } else {
            chunk
        }

        transcription.processAudio(paddedChunk)
        offset = end
    }

    transcription.flush()

    // Post-processing
    if (transcription.getSegments().isNotEmpty()) {
        transcription.showStats()

        val nClusters = transcription.clusterUnknowns()
        if (nClusters > 0) {
            println("\n\uD83D\uDCCA Clustered unknowns into $nClusters speaker(s)")
        }

        // Self-improvement flow
        transcription.confirmOutliers()
        transcription.promptNaming()
        transcription.saveLibrary()
    }

    return transcription.getSegments()
}
