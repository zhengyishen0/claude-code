package com.voice.pipeline

import kotlinx.cinterop.*
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import platform.Foundation.*

/**
 * Voice library with two-phase speaker matching and auto-learning.
 *
 * Matching algorithm:
 * Phase 1: Check all speakers' boundary layers against threshold
 * Phase 2: If multiple matches, use core scores to disambiguate
 */
class VoiceLibrary(private val path: String) {

    private val speakers: MutableMap<String, SpeakerProfile> = mutableMapOf()
    private val json = Json { prettyPrint = true; ignoreUnknownKeys = true }

    init {
        load()
    }

    /**
     * Match an embedding against all speakers.
     * Returns: (speakerName?, score, confidence: "high"/"medium"/"low"/"conflict")
     */
    fun match(embedding: FloatArray): Triple<String?, Float, String> {
        if (speakers.isEmpty()) {
            return Triple(null, 0f, "low")
        }

        // Phase 1: Check boundary layers
        val boundaryMatches = mutableListOf<Triple<String, Float, SpeakerProfile>>()
        for ((name, profile) in speakers) {
            val score = profile.maxSimilarityToBoundary(embedding)
            if (score >= BOUNDARY_THRESHOLD) {
                boundaryMatches.add(Triple(name, score, profile))
            }
        }

        // No matches
        if (boundaryMatches.isEmpty()) {
            return Triple(null, 0f, "low")
        }

        // Single match
        if (boundaryMatches.size == 1) {
            val (name, score, _) = boundaryMatches[0]
            val confidence = if (score >= AUTO_LEARN_THRESHOLD) "high" else "medium"
            return Triple(name, score, confidence)
        }

        // Phase 2: Multiple matches - use core scores to disambiguate
        val coreScores = boundaryMatches.map { (name, _, profile) ->
            Triple(name, profile.maxSimilarityToCore(embedding), profile)
        }.sortedByDescending { it.second }

        val (bestName, bestScore, _) = coreScores[0]
        val (secondName, secondScore, _) = coreScores[1]

        // Check margin
        return if (bestScore - secondScore >= CONFLICT_MARGIN) {
            val confidence = if (bestScore >= AUTO_LEARN_THRESHOLD) "high" else "medium"
            Triple(bestName, bestScore, confidence)
        } else {
            // Conflict - can't disambiguate
            Triple("[$bestName/$secondName?]", bestScore, "conflict")
        }
    }

    /**
     * Auto-learn from high-confidence match.
     * Returns true if embedding was added.
     */
    fun autoLearn(name: String, embedding: FloatArray, score: Float): Boolean {
        if (score < AUTO_LEARN_THRESHOLD) return false

        val profile = speakers[name] ?: return false
        val result = profile.addEmbedding(embedding)

        if (result != "rejected") {
            save()
            return true
        }
        return false
    }

    /**
     * Add a new embedding to an existing or new speaker.
     */
    fun addEmbedding(name: String, embedding: FloatArray, forceBoundary: Boolean = false): String {
        val profile = speakers.getOrPut(name) { SpeakerProfile(name) }
        val result = profile.addEmbedding(embedding, forceBoundary)
        if (result != "rejected") {
            save()
        }
        return result
    }

    /**
     * Enroll a new speaker with initial embedding.
     */
    fun enrollSpeaker(name: String, embedding: FloatArray): Boolean {
        if (speakers.containsKey(name)) return false

        val profile = SpeakerProfile(name)
        profile.addEmbedding(embedding)
        speakers[name] = profile
        save()
        return true
    }

    /**
     * Get all speaker names.
     */
    fun getSpeakerNames(): List<String> = speakers.keys.toList()

    /**
     * Check if a speaker exists.
     */
    fun hasSpeaker(name: String): Boolean = speakers.containsKey(name)

    /**
     * Load library from JSON file.
     */
    @OptIn(ExperimentalForeignApi::class)
    private fun load() {
        if (path.isEmpty()) return

        try {
            val data = NSData.dataWithContentsOfFile(path) ?: return
            val jsonString = NSString.create(data, NSUTF8StringEncoding) as String? ?: return

            val libraryData = json.decodeFromString<LibraryData>(jsonString)

            for (speakerData in libraryData.speakers) {
                val profile = SpeakerProfile(speakerData.name)

                // Add core embeddings
                for (emb in speakerData.core) {
                    profile.addEmbedding(emb.toFloatArray())
                }

                // Add boundary embeddings
                for (emb in speakerData.boundary) {
                    profile.addEmbedding(emb.toFloatArray(), forceBoundary = true)
                }

                speakers[speakerData.name] = profile
            }

            println("Loaded voice library: ${speakers.size} speakers")
        } catch (e: Exception) {
            // File doesn't exist or invalid - start fresh
        }
    }

    /**
     * Save library to JSON file.
     */
    @OptIn(ExperimentalForeignApi::class)
    fun save() {
        if (path.isEmpty()) return

        try {
            val data = LibraryData(
                speakers = speakers.map { (name, profile) ->
                    SpeakerData(
                        name = name,
                        core = profile.getCoreEmbeddings(),
                        boundary = profile.getBoundaryEmbeddings(),
                        centroid = profile.getCentroid(),
                        stdDev = profile.getStdDev(),
                        allDistances = profile.getAllDistances()
                    )
                }
            )
            val jsonString = json.encodeToString(data)

            val nsString = jsonString as NSString
            nsString.writeToFile(path, atomically = true, encoding = NSUTF8StringEncoding, error = null)
        } catch (e: Exception) {
            println("Warning: Could not save voice library to $path: ${e.message}")
        }
    }
}

@Serializable
data class LibraryData(
    val speakers: List<SpeakerData>
)

@Serializable
data class SpeakerData(
    val name: String,
    val core: List<List<Float>>,
    val boundary: List<List<Float>>,
    val centroid: List<Float>?,
    val stdDev: Float,
    val allDistances: List<Float>
)
