#!/bin/bash
# Setup script for Voice Pipeline
# Downloads models and dependencies

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VOICE_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== Voice Pipeline Setup ==="
echo "Root: $VOICE_DIR"
echo ""

# 0. Check for Java 17+ (required for KMP/Gradle)
echo "[Checking Java]"
if [ -n "$JAVA_HOME" ] && [ -x "$JAVA_HOME/bin/java" ]; then
    JAVA_VERSION=$("$JAVA_HOME/bin/java" -version 2>&1 | head -1 | sed -E 's/.*"([0-9]+).*/\1/')
    if [ "$JAVA_VERSION" -ge 17 ] 2>/dev/null; then
        echo "  [OK] Java $JAVA_VERSION found (JAVA_HOME=$JAVA_HOME)"
    else
        echo "  [!] Java $JAVA_VERSION found, but Java 17+ required for KMP"
        echo "      Install: brew install openjdk@17"
        echo "      Then: export JAVA_HOME=\"/opt/homebrew/opt/openjdk@17\""
    fi
elif [ -d "/opt/homebrew/opt/openjdk@17" ]; then
    echo "  [OK] Java 17 found at /opt/homebrew/opt/openjdk@17"
    echo "      Set: export JAVA_HOME=\"/opt/homebrew/opt/openjdk@17\""
elif command -v java &> /dev/null; then
    JAVA_VERSION=$(java -version 2>&1 | head -1 | sed -E 's/.*"([0-9]+).*/\1/')
    if [ "$JAVA_VERSION" -ge 17 ] 2>/dev/null; then
        echo "  [OK] Java $JAVA_VERSION found"
    else
        echo "  [!] Java found but version $JAVA_VERSION < 17"
        echo "      Install: brew install openjdk@17"
    fi
else
    echo "  [!] Java not found (required for KMP pipeline)"
    echo "      Install: brew install openjdk@17"
    echo "      Then: export JAVA_HOME=\"/opt/homebrew/opt/openjdk@17\""
fi
echo ""

# Create directories
mkdir -p "$VOICE_DIR/models/onnx"
mkdir -p "$VOICE_DIR/models/coreml"
mkdir -p "$VOICE_DIR/models/assets"

# 1. Download Silero VAD (ONNX)
VAD_PATH="$VOICE_DIR/models/onnx/silero_vad.onnx"
if [ -f "$VAD_PATH" ]; then
    echo "[OK] Silero VAD already downloaded"
else
    echo "[*] Downloading Silero VAD..."
    curl -L -o "$VAD_PATH" \
        "https://github.com/snakers4/silero-vad/raw/master/src/silero_vad/data/silero_vad.onnx"
    echo "[OK] Silero VAD downloaded"
fi

# 2. Download ONNX Runtime (for KMP pipeline)
KMP_LIBS="$VOICE_DIR/pipelines/kmp/libs"
ORT_VERSION="1.17.0"
ORT_DIR="$KMP_LIBS/onnxruntime-osx-arm64-$ORT_VERSION"

if [ -d "$ORT_DIR" ]; then
    echo "[OK] ONNX Runtime $ORT_VERSION already downloaded"
else
    echo "[*] Downloading ONNX Runtime $ORT_VERSION..."
    mkdir -p "$KMP_LIBS"
    curl -L -o /tmp/onnxruntime.tgz \
        "https://github.com/microsoft/onnxruntime/releases/download/v$ORT_VERSION/onnxruntime-osx-arm64-$ORT_VERSION.tgz"
    tar -xzf /tmp/onnxruntime.tgz -C "$KMP_LIBS/"
    rm /tmp/onnxruntime.tgz
    echo "[OK] ONNX Runtime downloaded"
fi

# 3. Build ONNX C wrapper (for KMP pipeline)
WRAPPER_DIR="$KMP_LIBS/onnx_wrapper"
if [ -f "$WRAPPER_DIR/build.sh" ]; then
    echo "[*] Building ONNX C wrapper..."
    "$WRAPPER_DIR/build.sh"
    echo "[OK] ONNX C wrapper built"
fi

# 4. Check for CoreML models
echo ""
echo "[Checking CoreML models]"
COREML_DIR="$VOICE_DIR/models/coreml"
for model in "sensevoice-500-itn.mlmodelc" "xvector.mlmodelc" "silero-vad.mlmodelc"; do
    if [ -d "$COREML_DIR/$model" ]; then
        echo "  [OK] $model"
    else
        echo "  [!] $model - not found (run conversion scripts)"
    fi
done

# 5. Check for ONNX ASR/Speaker models
echo ""
echo "[Checking ONNX models]"
ONNX_DIR="$VOICE_DIR/models/onnx"
if [ -f "$ONNX_DIR/sensevoice.onnx" ] && [ -f "$ONNX_DIR/xvector.onnx" ]; then
    echo "  [OK] ASR and Speaker models exist"
else
    echo "  [!] ASR/Speaker ONNX models not found"
    echo "      Run: python scripts/convert.py all --format onnx"
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "To convert models:"
echo "  python scripts/convert.py asr           # CoreML ASR"
echo "  python scripts/convert.py speaker       # CoreML Speaker"
echo "  python scripts/convert.py all --format onnx  # All ONNX"
echo ""
echo "To build KMP pipeline:"
echo "  cd pipelines/kmp && ./gradlew linkReleaseExecutableMacos"
