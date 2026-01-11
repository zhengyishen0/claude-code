import Foundation

/// Voice Library - Self-Improving Speaker Profile Management
///
/// Ported from Python's live.py VoiceLibrary class.
/// Implements two-layer profiles with two-phase matching and auto-learning.
///
/// Key concepts:
/// - Core embeddings: High-confidence samples (within 1σ of centroid)
/// - Boundary embeddings: Medium-confidence samples (1-2σ from centroid)
/// - Two-phase matching: Boundary screening → Core refinement
/// - Auto-learning: High-confidence matches automatically improve profiles
class VoiceLibrary {
    private var profiles: [String: SpeakerProfile] = [:]

    // MARK: - Enrollment

    /// Enroll a new speaker with initial embedding
    func enroll(name: String, embedding: [Float]) {
        // Normalize embedding
        let normalized = normalize(embedding)
        profiles[name] = SpeakerProfile(name: name, initialEmbedding: normalized)
    }

    /// Remove a speaker from the library
    func remove(name: String) {
        profiles.removeValue(forKey: name)
    }

    // MARK: - Identification (Two-Phase Matching)

    /// Identify speaker from embedding using two-phase matching.
    ///
    /// Phase 1 (Boundary): Quick screening against all centroids
    /// Phase 2 (Core): Detailed matching against top candidates
    ///
    /// Returns: (speaker_name, match_result) or (nil, _) if no match
    func identify(_ embedding: [Float]) -> (String?, MatchResult) {
        guard !profiles.isEmpty else {
            return (nil, MatchResult(similarity: 0, confidence: .none, phase: .boundary))
        }

        let normalized = normalize(embedding)

        // Phase 1: Boundary screening - get all matches
        var candidates: [(String, MatchResult)] = []

        for (name, profile) in profiles {
            let result = profile.match(normalized)
            if result.confidence != .none {
                candidates.append((name, result))
            }
        }

        // No candidates passed boundary screening
        guard !candidates.isEmpty else {
            return (nil, MatchResult(similarity: 0, confidence: .none, phase: .boundary))
        }

        // Sort by similarity (highest first)
        candidates.sort { $0.1.similarity > $1.1.similarity }

        // Get best candidate
        let (bestName, bestResult) = candidates[0]

        // Check for conflicts (close second candidate)
        if candidates.count >= 2 {
            let secondResult = candidates[1].1
            let margin = bestResult.similarity - secondResult.similarity

            // If margin is too small, reduce confidence
            if margin < 0.05 && bestResult.confidence == .high {
                // Conflict detected - demote to medium confidence
                return (bestName, MatchResult(
                    similarity: bestResult.similarity,
                    confidence: .medium,
                    phase: .core,
                    avgCoreSimilarity: bestResult.avgCoreSimilarity
                ))
            }
        }

        return (bestName, bestResult)
    }

    /// Get similarity scores for all speakers
    func identifyAll(_ embedding: [Float]) -> [(String, Float)] {
        let normalized = normalize(embedding)

        return profiles.map { (name, profile) in
            let result = profile.match(normalized)
            return (name, result.similarity)
        }.sorted { $0.1 > $1.1 }
    }

    // MARK: - Auto-Learning

    /// Auto-learn from high-confidence identification.
    /// Only call this when confidence >= .high
    func autoLearn(speaker: String, embedding: [Float]) {
        guard var profile = profiles[speaker] else { return }

        let normalized = normalize(embedding)
        profile.addEmbedding(normalized)
        profiles[speaker] = profile
    }

    /// Manually add embedding to speaker (for user-tagged segments)
    func addSample(speaker: String, embedding: [Float]) {
        guard var profile = profiles[speaker] else { return }

        let normalized = normalize(embedding)
        profile.addEmbedding(normalized)
        profiles[speaker] = profile
    }

    // MARK: - Query

    /// Get all speaker profiles
    func allProfiles() -> [SpeakerProfile] {
        Array(profiles.values).sorted { $0.name < $1.name }
    }

    /// Get profile for specific speaker
    func profile(for name: String) -> SpeakerProfile? {
        profiles[name]
    }

    /// List all speaker names
    func speakerNames() -> [String] {
        Array(profiles.keys).sorted()
    }

    // MARK: - Persistence

    func save(to url: URL) {
        do {
            let data = try JSONEncoder().encode(profiles)
            try data.write(to: url)
        } catch {
            print("Failed to save voice library: \(error)")
        }
    }

    func load(from url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        do {
            let data = try Data(contentsOf: url)
            profiles = try JSONDecoder().decode([String: SpeakerProfile].self, from: data)
        } catch {
            print("Failed to load voice library: \(error)")
        }
    }

    // MARK: - Utilities

    private func normalize(_ embedding: [Float]) -> [Float] {
        let norm = sqrt(embedding.reduce(0) { $0 + $1 * $1 })
        guard norm > 0 else { return embedding }
        return embedding.map { $0 / norm }
    }
}
