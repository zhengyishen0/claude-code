package com.voice.core

import kotlin.math.sqrt

/**
 * Compute cosine similarity between two vectors.
 * Returns value in range [-1, 1] where 1 means identical direction.
 */
fun cosineSimilarity(a: FloatArray, b: FloatArray): Float {
    require(a.size == b.size) { "Vectors must have same size" }

    var dotProduct = 0f
    var normA = 0f
    var normB = 0f

    for (i in a.indices) {
        dotProduct += a[i] * b[i]
        normA += a[i] * a[i]
        normB += b[i] * b[i]
    }

    val denominator = sqrt(normA) * sqrt(normB)
    return if (denominator > 1e-10f) dotProduct / denominator else 0f
}

/**
 * Compute cosine distance between two vectors.
 * Returns value in range [0, 2] where 0 means identical direction.
 */
fun cosineDistance(a: FloatArray, b: FloatArray): Float {
    return 1f - cosineSimilarity(a, b)
}

/**
 * Compute L2 (Euclidean) norm of a vector.
 */
fun l2Norm(v: FloatArray): Float {
    var sum = 0f
    for (x in v) {
        sum += x * x
    }
    return sqrt(sum)
}

/**
 * Normalize a vector to unit length (L2 normalization).
 * Returns a new normalized array.
 */
fun normalize(v: FloatArray): FloatArray {
    val norm = l2Norm(v)
    if (norm < 1e-10f) return v.copyOf()
    return FloatArray(v.size) { i -> v[i] / norm }
}

/**
 * Compute the centroid (mean) of a list of vectors.
 */
fun computeCentroid(vectors: List<FloatArray>): FloatArray? {
    if (vectors.isEmpty()) return null

    val dim = vectors[0].size
    val centroid = FloatArray(dim)

    for (v in vectors) {
        for (i in v.indices) {
            centroid[i] += v[i]
        }
    }

    val n = vectors.size.toFloat()
    for (i in centroid.indices) {
        centroid[i] /= n
    }

    return centroid
}

/**
 * Compute standard deviation of distances from centroid.
 */
fun computeStdDev(distances: List<Float>): Float {
    if (distances.size < 2) return 0.2f  // Default std dev

    val mean = distances.sum() / distances.size
    var variance = 0f
    for (d in distances) {
        val diff = d - mean
        variance += diff * diff
    }
    variance /= (distances.size - 1)

    return sqrt(variance).coerceAtLeast(0.05f)  // Minimum std dev
}
