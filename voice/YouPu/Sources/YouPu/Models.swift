import Foundation

// MARK: - Transcript Segment

/// A segment of transcribed speech with optional speaker identification
struct TranscriptSegment: Identifiable {
    let id: UUID
    let timestamp: String
    let text: String
    var speaker: String?
    let audioData: Data?  // Raw audio for this segment
    let embedding: [Float]?  // Speaker embedding for matching

    init(
        id: UUID = UUID(),
        timestamp: String = "",
        text: String,
        speaker: String? = nil,
        audioData: Data? = nil,
        embedding: [Float]? = nil
    ) {
        self.id = id
        self.timestamp = timestamp.isEmpty ? Self.currentTimestamp() : timestamp
        self.text = text
        self.speaker = speaker
        self.audioData = audioData
        self.embedding = embedding
    }

    static func currentTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }
}

// MARK: - Speaker Profile (Two-Layer Architecture)

/// Speaker profile with core and boundary embeddings for self-improving identification.
///
/// Architecture (ported from Python):
/// - Core embeddings: High-confidence samples (within 1σ of centroid)
/// - Boundary embeddings: Medium-confidence samples (1-2σ from centroid)
/// - Centroid: Average of core embeddings, used for initial matching
struct SpeakerProfile: Codable {
    let name: String
    var coreEmbeddings: [[Float]]      // Max 5, within 1σ
    var boundaryEmbeddings: [[Float]]  // Max 10, 1-2σ from centroid
    var centroid: [Float]              // Average of core embeddings
    var sampleCount: Int               // Total samples used for training
    let createdAt: Date

    // Derived property for UI
    var confidenceLevel: Int {
        // 1-5 scale based on core embeddings count
        min(5, coreEmbeddings.count)
    }

    init(name: String, initialEmbedding: [Float]) {
        self.name = name
        self.coreEmbeddings = [initialEmbedding]
        self.boundaryEmbeddings = []
        self.centroid = initialEmbedding
        self.sampleCount = 1
        self.createdAt = Date()
    }

    // MARK: - Core Operations (ported from Python)

    /// Add embedding to profile with automatic layer classification
    mutating func addEmbedding(_ embedding: [Float]) {
        let distance = cosineSimilarity(embedding, centroid)

        // Calculate σ (standard deviation) from core embeddings
        let sigma = calculateSigma()

        if distance >= (1.0 - sigma) {
            // Within 1σ: add to core
            addToCore(embedding)
        } else if distance >= (1.0 - 2 * sigma) {
            // 1-2σ: add to boundary
            addToBoundary(embedding)
        }
        // Beyond 2σ: reject (too different)

        sampleCount += 1
    }

    private mutating func addToCore(_ embedding: [Float]) {
        coreEmbeddings.append(embedding)

        // Keep max 5 core embeddings (remove oldest)
        if coreEmbeddings.count > 5 {
            coreEmbeddings.removeFirst()
        }

        // Update centroid
        updateCentroid()
    }

    private mutating func addToBoundary(_ embedding: [Float]) {
        boundaryEmbeddings.append(embedding)

        // Keep max 10 boundary embeddings
        if boundaryEmbeddings.count > 10 {
            boundaryEmbeddings.removeFirst()
        }
    }

    private mutating func updateCentroid() {
        guard !coreEmbeddings.isEmpty else { return }

        let dim = coreEmbeddings[0].count
        var sum = [Float](repeating: 0, count: dim)

        for emb in coreEmbeddings {
            for i in 0..<dim {
                sum[i] += emb[i]
            }
        }

        let count = Float(coreEmbeddings.count)
        centroid = sum.map { $0 / count }

        // Normalize centroid
        let norm = sqrt(centroid.reduce(0) { $0 + $1 * $1 })
        if norm > 0 {
            centroid = centroid.map { $0 / norm }
        }
    }

    private func calculateSigma() -> Float {
        guard coreEmbeddings.count >= 2 else { return 0.1 }  // Default σ

        let distances = coreEmbeddings.map { cosineSimilarity($0, centroid) }
        let mean = distances.reduce(0, +) / Float(distances.count)
        let variance = distances.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Float(distances.count)
        return sqrt(variance)
    }

    /// Match embedding against this profile (two-phase matching)
    func match(_ embedding: [Float]) -> MatchResult {
        // Phase 1: Boundary screening
        let centroidSim = cosineSimilarity(embedding, centroid)

        // Quick reject if too far from centroid
        let sigma = calculateSigma()
        if centroidSim < (1.0 - 3 * sigma) {
            return MatchResult(similarity: centroidSim, confidence: .none, phase: .boundary)
        }

        // Phase 2: Core refinement
        let coreSims = coreEmbeddings.map { cosineSimilarity(embedding, $0) }
        let maxCoreSim = coreSims.max() ?? 0
        let avgCoreSim = coreSims.reduce(0, +) / Float(max(1, coreSims.count))

        // Determine confidence
        let confidence: MatchConfidence
        if maxCoreSim >= 0.55 && avgCoreSim >= 0.45 {
            confidence = .high
        } else if maxCoreSim >= 0.40 {
            confidence = .medium
        } else if centroidSim >= 0.30 {
            confidence = .low
        } else {
            confidence = .none
        }

        return MatchResult(
            similarity: maxCoreSim,
            confidence: confidence,
            phase: .core,
            avgCoreSimilarity: avgCoreSim
        )
    }
}

// MARK: - Match Result

struct MatchResult {
    let similarity: Float
    let confidence: MatchConfidence
    let phase: MatchPhase
    var avgCoreSimilarity: Float = 0

    enum MatchPhase {
        case boundary  // Quick screening
        case core      // Detailed matching
    }
}

enum MatchConfidence: Int, Comparable {
    case none = 0
    case low = 1
    case medium = 2
    case high = 3

    static func < (lhs: MatchConfidence, rhs: MatchConfidence) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Pipeline Metrics

struct PipelineMetrics {
    var vadMs: Int = 0
    var asrMs: Int = 0
    var speakerIdMs: Int = 0
    var totalMs: Int { vadMs + asrMs + speakerIdMs }

    var accuracy: Double = 0.0
    var autoLearnedCount: Int = 0
}

// MARK: - Utility Functions

func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
    guard a.count == b.count, !a.isEmpty else { return 0 }

    var dot: Float = 0
    var normA: Float = 0
    var normB: Float = 0

    for i in 0..<a.count {
        dot += a[i] * b[i]
        normA += a[i] * a[i]
        normB += b[i] * b[i]
    }

    let denom = sqrt(normA) * sqrt(normB)
    return denom > 0 ? dot / denom : 0
}
