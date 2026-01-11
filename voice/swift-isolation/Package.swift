// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VoiceIsolation",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "voice-isolate",
            path: "Sources"
        )
    ]
)
