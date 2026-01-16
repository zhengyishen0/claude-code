// swift-tools-version: 5.9
import PackageDescription

// Path to KMP framework
let kmpFrameworkPath = "/Users/zhengyishen/Codes/claude-code-kmp-framework/voice/pipelines/kmp/build/bin/macos/releaseFramework"

let package = Package(
    name: "Voice",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Voice",
            path: "Voice",
            resources: [.copy("Resources")],
            swiftSettings: [
                .unsafeFlags([
                    "-F", kmpFrameworkPath
                ])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", kmpFrameworkPath,
                    "-framework", "VoicePipeline",
                    "-Xlinker", "-rpath",
                    "-Xlinker", kmpFrameworkPath
                ])
            ]
        )
    ]
)
