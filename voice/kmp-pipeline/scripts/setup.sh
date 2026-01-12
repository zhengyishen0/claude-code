#!/bin/bash
# Setup script for KMP Voice Pipeline
# Downloads ONNX Runtime and ONNX models

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== KMP Voice Pipeline Setup ==="
echo ""

# 1. Download ONNX Runtime
ORT_VERSION="1.17.0"
ORT_DIR="$PROJECT_DIR/libs/onnxruntime-osx-arm64-$ORT_VERSION"

if [ -d "$ORT_DIR" ]; then
    echo "[OK] ONNX Runtime $ORT_VERSION already downloaded"
else
    echo "[*] Downloading ONNX Runtime $ORT_VERSION..."
    curl -L -o /tmp/onnxruntime.tgz \
        "https://github.com/microsoft/onnxruntime/releases/download/v$ORT_VERSION/onnxruntime-osx-arm64-$ORT_VERSION.tgz"
    tar -xzf /tmp/onnxruntime.tgz -C "$PROJECT_DIR/libs/"
    rm /tmp/onnxruntime.tgz
    echo "[OK] ONNX Runtime downloaded"
fi

# 2. Download ONNX models
MODELS_DIR="$PROJECT_DIR/Models/onnx"
mkdir -p "$MODELS_DIR"

# Silero VAD
if [ -f "$MODELS_DIR/silero_vad.onnx" ]; then
    echo "[OK] Silero VAD model already downloaded"
else
    echo "[*] Downloading Silero VAD model..."
    curl -L -o "$MODELS_DIR/silero_vad.onnx" \
        "https://github.com/snakers4/silero-vad/raw/master/src/silero_vad/data/silero_vad.onnx"
    echo "[OK] Silero VAD downloaded"
fi

# SenseVoice and xvector need to be exported from Python
# Check if they exist
if [ -f "$MODELS_DIR/sensevoice.onnx" ] && [ -f "$MODELS_DIR/xvector.onnx" ]; then
    echo "[OK] ASR and Speaker models already exist"
else
    echo ""
    echo "[!] ASR (sensevoice.onnx) and Speaker (xvector.onnx) models need to be exported."
    echo "    Run: python3 scripts/export_onnx.py"
    echo ""
fi

# 3. Build C wrapper library
echo ""
echo "[*] Building ONNX C wrapper library..."
"$PROJECT_DIR/libs/onnx_wrapper/build.sh"

# 4. Build KissFFT library (if not exists)
if [ -f "$PROJECT_DIR/libs/libKissFFT.a" ]; then
    echo "[OK] KissFFT library already built"
else
    echo "[*] Building KissFFT library..."
    # Assuming kiss_fft source is available
    if [ -f "$PROJECT_DIR/libs/kiss_fft.c" ]; then
        clang -c -O2 -arch arm64 "$PROJECT_DIR/libs/kiss_fft.c" -o "$PROJECT_DIR/libs/kiss_fft.o"
        clang -c -O2 -arch arm64 "$PROJECT_DIR/libs/kiss_fftr.c" -o "$PROJECT_DIR/libs/kiss_fftr.o"
        ar rcs "$PROJECT_DIR/libs/libKissFFT.a" "$PROJECT_DIR/libs/kiss_fft.o" "$PROJECT_DIR/libs/kiss_fftr.o"
        echo "[OK] KissFFT built"
    else
        echo "[!] KissFFT source not found - skipping"
    fi
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "To build the project:"
echo "  ./gradlew linkDebugExecutableMacos"
echo ""
echo "To run:"
echo "  ./build/bin/macos/debugExecutable/kmp-pipeline.kexe live"
echo "  ./build/bin/macos/debugExecutable/kmp-pipeline.kexe benchmark"
