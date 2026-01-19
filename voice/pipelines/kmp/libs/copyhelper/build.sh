#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIBS_DIR="$(dirname "$SCRIPT_DIR")"

echo "Building CopyHelper library for arm64 and x86_64..."

# Build for arm64
echo "  Building arm64..."
clang -c -O3 -arch arm64 \
    -o "$SCRIPT_DIR/copyhelper_arm64.o" \
    "$SCRIPT_DIR/copyhelper.c"

ar rcs "$SCRIPT_DIR/libCopyHelper_arm64.a" "$SCRIPT_DIR/copyhelper_arm64.o"

# Build for x86_64
echo "  Building x86_64..."
clang -c -O3 -arch x86_64 \
    -o "$SCRIPT_DIR/copyhelper_x86_64.o" \
    "$SCRIPT_DIR/copyhelper.c"

ar rcs "$SCRIPT_DIR/libCopyHelper_x86_64.a" "$SCRIPT_DIR/copyhelper_x86_64.o"

# Copy to libs directory
cp "$SCRIPT_DIR/libCopyHelper_arm64.a" "$LIBS_DIR/libCopyHelper_arm64.a"
cp "$SCRIPT_DIR/libCopyHelper_x86_64.a" "$LIBS_DIR/libCopyHelper_x86_64.a"

# Keep original for backward compatibility
cp "$SCRIPT_DIR/libCopyHelper_arm64.a" "$SCRIPT_DIR/libCopyHelper.a"

echo "Built:"
ls -la "$LIBS_DIR"/libCopyHelper*.a
