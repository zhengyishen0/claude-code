// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "YouPu",
    platforms: [
        .macOS(.v14)  // macOS 14+ for Voice Isolation
    ],
    products: [
        .executable(name: "YouPu", targets: ["YouPu"])
    ],
    dependencies: [
        // FluidAudio for VAD (Silero CoreML)
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.7.9")
    ],
    targets: [
        .executableTarget(
            name: "YouPu",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio")
            ],
            path: "Sources/YouPu",
            resources: [
                .copy("Models")  // CoreML models directory
            ]
        )
    ]
)
