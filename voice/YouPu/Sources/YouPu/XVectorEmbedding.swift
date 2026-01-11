import Foundation
import CoreML
import Accelerate

/// X-vector speaker embedding extraction using CoreML.
///
/// Extracts 512-dimensional speaker embeddings for voice identification.
/// Converted from SpeechBrain's spkrec-xvect-voxceleb model.
///
/// Performance: ~4ms per 3-second audio segment on Apple Silicon.
class XVectorEmbedding {
    private let model: MLModel
    private let inputName = "audio"
    private let outputName = "embedding"

    // Expected input: 3 seconds of 16kHz audio = 48000 samples
    static let sampleRate: Int = 16000
    static let expectedSamples: Int = 48000  // 3 seconds

    init() throws {
        // Load compiled CoreML model
        guard let modelURL = ModelLoader.findModel(named: "xvector", withExtension: "mlmodelc") else {
            throw XVectorError.modelNotFound
        }

        print("Loading x-vector model from: \(modelURL.path)")

        let config = MLModelConfiguration()
        config.computeUnits = .all  // Use ANE when available

        self.model = try MLModel(contentsOf: modelURL, configuration: config)
        print("x-vector model loaded successfully")
    }

    /// Extract speaker embedding from audio samples.
    ///
    /// - Parameter audio: Audio samples at 16kHz, mono
    /// - Returns: 512-dimensional normalized embedding
    func extractEmbedding(from audio: [Float]) -> [Float]? {
        // Pad or truncate to expected length
        let processedAudio = prepareAudio(audio)

        // Create MLMultiArray input
        guard let inputArray = try? MLMultiArray(shape: [1, NSNumber(value: Self.expectedSamples)], dataType: .float32) else {
            return nil
        }

        // Copy audio data
        for i in 0..<Self.expectedSamples {
            inputArray[i] = NSNumber(value: processedAudio[i])
        }

        // Create input provider
        let inputFeatures = try? MLDictionaryFeatureProvider(dictionary: [inputName: inputArray])
        guard let input = inputFeatures else { return nil }

        // Run inference
        guard let output = try? model.prediction(from: input) else {
            return nil
        }

        // Extract embedding
        guard let embeddingArray = output.featureValue(for: outputName)?.multiArrayValue else {
            return nil
        }

        // Convert to [Float] and normalize
        var embedding = multiArrayToFloatArray(embeddingArray)
        normalize(&embedding)

        return embedding
    }

    /// Extract embedding with timing information.
    func extractEmbeddingTimed(from audio: [Float]) -> (embedding: [Float]?, timeMs: Double) {
        let start = CFAbsoluteTimeGetCurrent()
        let embedding = extractEmbedding(from: audio)
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        return (embedding, elapsed)
    }

    // MARK: - Private Helpers

    private func prepareAudio(_ audio: [Float]) -> [Float] {
        var result: [Float]

        if audio.count < Self.expectedSamples {
            // Pad with zeros
            result = audio + [Float](repeating: 0, count: Self.expectedSamples - audio.count)
        } else if audio.count > Self.expectedSamples {
            // Truncate (take middle portion for better representation)
            let start = (audio.count - Self.expectedSamples) / 2
            result = Array(audio[start..<(start + Self.expectedSamples)])
        } else {
            result = audio
        }

        return result
    }

    private func multiArrayToFloatArray(_ array: MLMultiArray) -> [Float] {
        let count = array.count
        var result = [Float](repeating: 0, count: count)

        let pointer = array.dataPointer.bindMemory(to: Float.self, capacity: count)
        for i in 0..<count {
            result[i] = pointer[i]
        }

        return result
    }

    private func normalize(_ embedding: inout [Float]) {
        var norm: Float = 0
        vDSP_svesq(embedding, 1, &norm, vDSP_Length(embedding.count))
        norm = sqrt(norm)

        if norm > 0 {
            var scale = 1.0 / norm
            vDSP_vsmul(embedding, 1, &scale, &embedding, 1, vDSP_Length(embedding.count))
        }
    }
}

// MARK: - Errors

enum XVectorError: Error, LocalizedError {
    case modelNotFound
    case inferenceError

    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "x-vector CoreML model not found in bundle"
        case .inferenceError:
            return "x-vector inference failed"
        }
    }
}
