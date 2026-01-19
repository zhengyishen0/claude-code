#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIBS_DIR="$(dirname "$SCRIPT_DIR")"

echo "Building KissFFT library for arm64 and x86_64..."

# Build for arm64
echo "  Building arm64..."
clang -c -O3 -arch arm64 -DKISS_FFT_USE_ALLOCA=1 \
    -I"$SCRIPT_DIR" \
    -o "$SCRIPT_DIR/kiss_fft_arm64.o" \
    "$SCRIPT_DIR/kiss_fft.c"

clang -c -O3 -arch arm64 -DKISS_FFT_USE_ALLOCA=1 \
    -I"$SCRIPT_DIR" \
    -o "$SCRIPT_DIR/kiss_fftr_arm64.o" \
    "$SCRIPT_DIR/tools/kiss_fftr.c"

ar rcs "$SCRIPT_DIR/libKissFFT_arm64.a" \
    "$SCRIPT_DIR/kiss_fft_arm64.o" \
    "$SCRIPT_DIR/kiss_fftr_arm64.o"

# Build for x86_64
echo "  Building x86_64..."
clang -c -O3 -arch x86_64 -DKISS_FFT_USE_ALLOCA=1 \
    -I"$SCRIPT_DIR" \
    -o "$SCRIPT_DIR/kiss_fft_x86_64.o" \
    "$SCRIPT_DIR/kiss_fft.c"

clang -c -O3 -arch x86_64 -DKISS_FFT_USE_ALLOCA=1 \
    -I"$SCRIPT_DIR" \
    -o "$SCRIPT_DIR/kiss_fftr_x86_64.o" \
    "$SCRIPT_DIR/tools/kiss_fftr.c"

ar rcs "$SCRIPT_DIR/libKissFFT_x86_64.a" \
    "$SCRIPT_DIR/kiss_fft_x86_64.o" \
    "$SCRIPT_DIR/kiss_fftr_x86_64.o"

# Copy to libs directory for each architecture
cp "$SCRIPT_DIR/libKissFFT_arm64.a" "$LIBS_DIR/libKissFFT_arm64.a"
cp "$SCRIPT_DIR/libKissFFT_x86_64.a" "$LIBS_DIR/libKissFFT_x86_64.a"

# Keep the original name for backward compatibility (arm64)
cp "$SCRIPT_DIR/libKissFFT_arm64.a" "$LIBS_DIR/libKissFFT.a"

echo "Built:"
ls -la "$LIBS_DIR"/libKissFFT*.a
