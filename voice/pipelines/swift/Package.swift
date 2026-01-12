// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PipelineTest",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/AudioKit/KissFFT.git", from: "1.0.0"),
        .package(url: "https://github.com/jkrukowski/swift-sentencepiece", from: "0.0.3")
    ],
    targets: [
        .executableTarget(
            name: "PipelineTest",
            dependencies: [
                "KissFFT",
                .product(name: "SentencepieceTokenizer", package: "swift-sentencepiece")
            ],
            path: "Sources"
        )
    ]
)
