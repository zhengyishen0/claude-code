#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIBS_DIR="$(dirname "$SCRIPT_DIR")"
ORT_ARM64_DIR="$LIBS_DIR/onnxruntime-osx-arm64-1.17.0"
ORT_X86_64_DIR="$LIBS_DIR/onnxruntime-osx-x86_64-1.17.0"

echo "Building ONNX wrapper library for arm64 and x86_64..."

# Build for arm64
echo "  Building arm64..."
clang -c -O2 -arch arm64 \
    -I"$ORT_ARM64_DIR/include" \
    -o "$SCRIPT_DIR/onnx_wrapper_arm64.o" \
    "$SCRIPT_DIR/onnx_wrapper.c"

ar rcs "$SCRIPT_DIR/libOnnxWrapper_arm64.a" "$SCRIPT_DIR/onnx_wrapper_arm64.o"

# Build for x86_64
echo "  Building x86_64..."
clang -c -O2 -arch x86_64 \
    -I"$ORT_X86_64_DIR/include" \
    -o "$SCRIPT_DIR/onnx_wrapper_x86_64.o" \
    "$SCRIPT_DIR/onnx_wrapper.c"

ar rcs "$SCRIPT_DIR/libOnnxWrapper_x86_64.a" "$SCRIPT_DIR/onnx_wrapper_x86_64.o"

# Copy to libs directory
cp "$SCRIPT_DIR/libOnnxWrapper_arm64.a" "$LIBS_DIR/libOnnxWrapper_arm64.a"
cp "$SCRIPT_DIR/libOnnxWrapper_x86_64.a" "$LIBS_DIR/libOnnxWrapper_x86_64.a"

# Keep original for backward compatibility
cp "$SCRIPT_DIR/libOnnxWrapper_arm64.a" "$SCRIPT_DIR/libOnnxWrapper.a"

echo "Built:"
ls -la "$LIBS_DIR"/libOnnxWrapper*.a
