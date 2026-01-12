#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ORT_DIR="$SCRIPT_DIR/../onnxruntime-osx-arm64-1.17.0"

echo "Building ONNX wrapper library..."

clang -c -O2 -arch arm64 \
    -I"$ORT_DIR/include" \
    -o "$SCRIPT_DIR/onnx_wrapper.o" \
    "$SCRIPT_DIR/onnx_wrapper.c"

ar rcs "$SCRIPT_DIR/libOnnxWrapper.a" "$SCRIPT_DIR/onnx_wrapper.o"

echo "Built: $SCRIPT_DIR/libOnnxWrapper.a"
ls -la "$SCRIPT_DIR/libOnnxWrapper.a"
