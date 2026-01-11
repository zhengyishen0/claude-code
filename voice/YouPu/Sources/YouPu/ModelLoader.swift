import Foundation

/// Helper to load CoreML models from various locations.
///
/// For development: loads from source directory
/// For deployment: loads from app bundle or specified path
struct ModelLoader {
    /// Find model URL by searching common locations
    static func findModel(named name: String, withExtension ext: String) -> URL? {
        // 1. Try Bundle.main (for app bundles)
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return url
        }

        // 2. Try relative to executable (for development)
        let executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        let executableDir = executableURL.deletingLastPathComponent()

        // Check in Models subdirectory relative to executable
        let devModelURL = executableDir
            .appendingPathComponent("Models")
            .appendingPathComponent("\(name).\(ext)")

        if FileManager.default.fileExists(atPath: devModelURL.path) {
            return devModelURL
        }

        // 3. Try source directory (for swift run)
        // Go up from .build/debug to find Sources
        var searchDir = executableDir
        for _ in 0..<5 {
            let sourceModelURL = searchDir
                .appendingPathComponent("Sources")
                .appendingPathComponent("YouPu")
                .appendingPathComponent("Models")
                .appendingPathComponent("\(name).\(ext)")

            if FileManager.default.fileExists(atPath: sourceModelURL.path) {
                return sourceModelURL
            }

            searchDir = searchDir.deletingLastPathComponent()
        }

        // 4. Try environment variable
        if let modelPath = ProcessInfo.processInfo.environment["YOUPU_MODEL_PATH"] {
            let envModelURL = URL(fileURLWithPath: modelPath)
                .appendingPathComponent("\(name).\(ext)")

            if FileManager.default.fileExists(atPath: envModelURL.path) {
                return envModelURL
            }
        }

        // 5. Try current working directory
        let cwdModelURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Models")
            .appendingPathComponent("\(name).\(ext)")

        if FileManager.default.fileExists(atPath: cwdModelURL.path) {
            return cwdModelURL
        }

        return nil
    }

    /// Get the Models directory path
    static var modelsDirectory: URL? {
        // Try to find any model to determine the directory
        if let xvectorURL = findModel(named: "xvector", withExtension: "mlmodelc") {
            return xvectorURL.deletingLastPathComponent()
        }

        if let senseVoiceURL = findModel(named: "sensevoice-500-itn", withExtension: "mlmodelc") {
            return senseVoiceURL.deletingLastPathComponent()
        }

        return nil
    }
}
