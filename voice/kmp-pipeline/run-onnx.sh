#!/bin/bash
# Run live transcription with ONNX Runtime backend
# Usage: ./run-onnx.sh [benchmark]

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Set Java home for Gradle
export JAVA_HOME="/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home"
export PATH="$JAVA_HOME/bin:$PATH"

echo "=== KMP Voice Pipeline - ONNX Runtime ==="
echo ""

# Step 1: Check/download ONNX Runtime
ORT_VERSION="1.17.0"
ORT_DIR="$SCRIPT_DIR/libs/onnxruntime-osx-arm64-$ORT_VERSION"

if [ ! -d "$ORT_DIR" ]; then
    echo "[1/4] Downloading ONNX Runtime $ORT_VERSION..."
    curl -L -o /tmp/onnxruntime.tgz \
        "https://github.com/microsoft/onnxruntime/releases/download/v$ORT_VERSION/onnxruntime-osx-arm64-$ORT_VERSION.tgz"
    tar -xzf /tmp/onnxruntime.tgz -C "$SCRIPT_DIR/libs/"
    rm /tmp/onnxruntime.tgz
else
    echo "[1/4] ONNX Runtime already downloaded"
fi

# Step 2: Check/download ONNX models
MODELS_DIR="$SCRIPT_DIR/Models/onnx"
mkdir -p "$MODELS_DIR"

if [ ! -f "$MODELS_DIR/silero_vad.onnx" ]; then
    echo "[2/4] Downloading Silero VAD model..."
    curl -L -o "$MODELS_DIR/silero_vad.onnx" \
        "https://github.com/snakers4/silero-vad/raw/master/src/silero_vad/data/silero_vad.onnx"
else
    echo "[2/4] Silero VAD model exists"
fi

# Check for ASR and Speaker models
if [ ! -f "$MODELS_DIR/sensevoice.onnx" ] || [ ! -f "$MODELS_DIR/xvector.onnx" ]; then
    echo ""
    echo "WARNING: ASR or Speaker models missing!"
    echo "  - sensevoice.onnx: $([ -f "$MODELS_DIR/sensevoice.onnx" ] && echo "OK" || echo "MISSING")"
    echo "  - xvector.onnx: $([ -f "$MODELS_DIR/xvector.onnx" ] && echo "OK" || echo "MISSING")"
    echo ""
    echo "To export these models, run: python3 scripts/export_onnx.py"
    echo "Or copy them from another location."
    echo ""
fi

# Step 3: Build C wrapper
echo "[3/4] Building ONNX C wrapper..."
"$SCRIPT_DIR/libs/onnx_wrapper/build.sh" 2>&1 | grep -E "(Built|error)" || true

# Step 4: Build Kotlin project
echo "[4/4] Building Kotlin project..."
./gradlew linkDebugExecutableMacos --quiet 2>&1 | grep -v "^$" | head -5 || true

echo ""
echo "=== Build Complete ==="
echo ""

# Run based on argument
if [ "$1" = "benchmark" ]; then
    echo "Running benchmark..."
    echo ""
    ./build/bin/macos/debugExecutable/kmp-pipeline.kexe benchmark
else
    echo "Starting live transcription with ONNX Runtime..."
    echo "(Press Ctrl+C to stop)"
    echo ""
    ./build/bin/macos/debugExecutable/kmp-pipeline.kexe live --onnx
fi
