# KMP Voice Pipeline

Kotlin Multiplatform voice transcription pipeline for macOS, supporting both CoreML and ONNX Runtime backends.

## Features

- **Voice Activity Detection (VAD)** - Silero VAD
- **Speech Recognition (ASR)** - SenseVoice (Chinese/English/Japanese/Korean)
- **Speaker Identification** - xvector embeddings
- **Two backends**: CoreML (fast, Neural Engine) and ONNX Runtime (cross-platform)

## Project Structure

```
kmp-pipeline/
├── src/macosMain/kotlin/com/voice/pipeline/
│   ├── Main.kt              # CLI entry point
│   ├── CoreMLInference.kt   # CoreML model wrapper
│   ├── ONNXInference.kt     # ONNX Runtime wrapper
│   ├── AudioCapture.kt      # Microphone input
│   ├── AudioProcessing.kt   # Mel spectrogram, FFT
│   ├── LiveTranscription.kt # Real-time pipeline
│   └── ...
├── libs/
│   ├── onnx_wrapper/        # C wrapper for ONNX Runtime
│   │   ├── onnx_wrapper.c
│   │   ├── onnx_wrapper.h
│   │   └── build.sh
│   └── onnxruntime-osx-arm64-*/  # (downloaded)
├── Models/
│   └── onnx/                # (downloaded)
│       ├── silero_vad.onnx
│       ├── sensevoice.onnx
│       └── xvector.onnx
└── scripts/
    ├── setup.sh             # Download dependencies
    └── export_onnx.py       # Export models to ONNX
```

## Setup

### Prerequisites

- macOS with Apple Silicon (M1/M2/M3/M4)
- JDK 17+ (for Gradle)
- Python 3.8+ (for model export)

### Quick Start

```bash
# 1. Run setup script (downloads ONNX Runtime and models)
chmod +x scripts/setup.sh
./scripts/setup.sh

# 2. Build the project
./gradlew linkDebugExecutableMacos

# 3. Run
./build/bin/macos/debugExecutable/kmp-pipeline.kexe live
```

## Usage

```bash
# Show help
./kmp-pipeline.kexe

# Live transcription (CoreML - default, fast)
./kmp-pipeline.kexe live

# Live transcription (ONNX Runtime - slower)
./kmp-pipeline.kexe live --onnx

# Process audio file
./kmp-pipeline.kexe file recording.wav
./kmp-pipeline.kexe file recording.wav --onnx

# Benchmark CoreML vs ONNX
./kmp-pipeline.kexe benchmark recording.wav

# Run tests
./kmp-pipeline.kexe test
```

## Performance Comparison

| Metric | CoreML | ONNX Runtime | Speedup |
|--------|--------|--------------|---------|
| Model Load | 265ms | 3,165ms | 12x |
| VAD | 57ms | 121ms | 2x |
| ASR | 1,846ms | 4,816ms | 2.6x |
| Speaker | 11ms | 316ms | 29x |
| **Total** | **1,915ms** | **5,254ms** | **2.7x** |

CoreML uses the Neural Engine for hardware acceleration. ONNX Runtime runs on CPU only (CoreML EP support planned).

## Dependencies

Downloaded by `setup.sh`:
- **ONNX Runtime 1.17.0** - Cross-platform ML runtime
- **Silero VAD** - Voice activity detection model
- **SenseVoice** - ASR model (exported from FunASR)
- **xvector** - Speaker embedding model (exported from SpeechBrain)

Included in repo:
- **KissFFT** - FFT library for audio processing

## Building from Source

```bash
# Build debug
./gradlew linkDebugExecutableMacos

# Build release (optimized)
./gradlew linkReleaseExecutableMacos

# Clean
./gradlew clean
```

## Notes

- CoreML models are located separately (see MODEL_DIR in Main.kt)
- ONNX VAD uses 512-sample chunks (32ms), CoreML uses 4096-sample chunks (256ms)
- The C wrapper simplifies ONNX Runtime's complex API for Kotlin/Native
