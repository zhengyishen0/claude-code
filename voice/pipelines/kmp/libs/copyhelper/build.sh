#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Building CopyHelper library..."

clang -c -O3 -arch arm64 \
    -o "$SCRIPT_DIR/copyhelper.o" \
    "$SCRIPT_DIR/copyhelper.c"

ar rcs "$SCRIPT_DIR/libCopyHelper.a" "$SCRIPT_DIR/copyhelper.o"

echo "Built: $SCRIPT_DIR/libCopyHelper.a"
ls -la "$SCRIPT_DIR/libCopyHelper.a"
