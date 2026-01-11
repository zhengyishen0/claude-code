// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PipelineTest",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/AudioKit/KissFFT.git", from: "1.0.0")
    ],
    targets: [
        .executableTarget(
            name: "PipelineTest",
            dependencies: ["KissFFT"],
            path: "Sources"
        )
    ]
)
