package com.voice.core

import kotlinx.serialization.Serializable

/**
 * Two-layer speaker profile with core and boundary embeddings.
 *
 * Core layer: Embeddings within 1σ of centroid (frequent voice patterns)
 * Boundary layer: Embeddings between 1σ and 2σ (edge-case patterns)
 *
 * This design allows for:
 * - Fast matching against core embeddings
 * - Graceful handling of voice variations
 * - Self-improvement through auto-learning
 */
@Serializable
class SpeakerProfile(val name: String) {

    // Core embeddings (within 1σ of centroid)
    private val core: MutableList<List<Float>> = mutableListOf()

    // Boundary embeddings (1σ to 2σ from centroid)
    private val boundary: MutableList<List<Float>> = mutableListOf()

    // Statistical tracking
    private var centroid: List<Float>? = null
    private var stdDev: Float = 0.2f
    private val allDistances: MutableList<Float> = mutableListOf()

    /**
     * Add a new embedding to the profile.
     * Returns "core", "boundary", or "rejected" based on where it was added.
     */
    fun addEmbedding(embedding: FloatArray, forceBoundary: Boolean = false): String {
        // Check diversity - don't add if too similar to existing
        val allEmbeddings = getAllEmbeddings()
        if (allEmbeddings.isNotEmpty()) {
            val minDist = allEmbeddings.minOf { cosineDistance(embedding, it) }
            if (minDist < MIN_DIVERSITY) {
                return "rejected"  // Too similar to existing
            }
        }

        // For first embedding, add to core
        if (centroid == null) {
            core.add(embedding.toList())
            centroid = embedding.toList()
            return "core"
        }

        // Compute distance from centroid
        val dist = cosineDistance(embedding, centroid!!.toFloatArray())
        allDistances.add(dist)
        stdDev = computeStdDev(allDistances)

        // Classify based on distance from centroid
        return when {
            forceBoundary -> {
                // Force to boundary (e.g., user-confirmed outlier)
                if (boundary.size < MAX_BOUNDARY) {
                    boundary.add(embedding.toList())
                    "boundary"
                } else {
                    "rejected"
                }
            }
            dist < stdDev -> {
                // Within 1σ → candidate for core
                if (core.size < MAX_CORE) {
                    core.add(embedding.toList())
                    updateCentroid()
                    "core"
                } else if (boundary.size < MAX_BOUNDARY) {
                    boundary.add(embedding.toList())
                    "boundary"
                } else {
                    "rejected"
                }
            }
            dist < 2 * stdDev -> {
                // Between 1σ and 2σ → boundary
                if (boundary.size < MAX_BOUNDARY) {
                    boundary.add(embedding.toList())
                    "boundary"
                } else {
                    "rejected"
                }
            }
            else -> {
                // Beyond 2σ → reject (too different)
                "rejected"
            }
        }
    }

    /**
     * Get maximum similarity to any embedding in the core layer.
     */
    fun maxSimilarityToCore(embedding: FloatArray): Float {
        if (core.isEmpty()) return 0f
        return core.maxOf { cosineSimilarity(embedding, it.toFloatArray()) }
    }

    /**
     * Get maximum similarity to any embedding in core + boundary layers.
     */
    fun maxSimilarityToBoundary(embedding: FloatArray): Float {
        val allEmbeddings = core + boundary
        if (allEmbeddings.isEmpty()) return 0f
        return allEmbeddings.maxOf { cosineSimilarity(embedding, it.toFloatArray()) }
    }

    /**
     * Get all embeddings (core + boundary).
     */
    private fun getAllEmbeddings(): List<FloatArray> {
        return (core + boundary).map { it.toFloatArray() }
    }

    /**
     * Update centroid based on core embeddings.
     */
    private fun updateCentroid() {
        if (core.isEmpty()) {
            centroid = null
            return
        }

        val dim = core[0].size
        val newCentroid = FloatArray(dim)

        for (emb in core) {
            for (i in emb.indices) {
                newCentroid[i] += emb[i]
            }
        }

        for (i in newCentroid.indices) {
            newCentroid[i] /= core.size
        }

        centroid = newCentroid.toList()
    }

    // Serialization helpers
    fun getCoreEmbeddings(): List<List<Float>> = core.toList()
    fun getBoundaryEmbeddings(): List<List<Float>> = boundary.toList()
    fun getCentroid(): List<Float>? = centroid
    fun getStdDev(): Float = stdDev
    fun getAllDistances(): List<Float> = allDistances.toList()

    fun setCoreEmbeddings(embeddings: List<List<Float>>) {
        core.clear()
        core.addAll(embeddings)
        updateCentroid()
    }

    fun setBoundaryEmbeddings(embeddings: List<List<Float>>) {
        boundary.clear()
        boundary.addAll(embeddings)
    }

    fun setStdDev(value: Float) {
        stdDev = value
    }

    fun setAllDistances(distances: List<Float>) {
        allDistances.clear()
        allDistances.addAll(distances)
    }

    companion object {
        fun fromData(
            name: String,
            core: List<List<Float>>,
            boundary: List<List<Float>>,
            centroid: List<Float>?,
            stdDev: Float,
            allDistances: List<Float>
        ): SpeakerProfile {
            return SpeakerProfile(name).apply {
                setCoreEmbeddings(core)
                setBoundaryEmbeddings(boundary)
                this.centroid = centroid
                setStdDev(stdDev)
                setAllDistances(allDistances)
            }
        }
    }
}

// Extension to convert List<Float> to FloatArray
private fun List<Float>.toFloatArray(): FloatArray = FloatArray(size) { this[it] }
