package com.voice.cli

// Default paths (relative to voice/ project root)
const val MODEL_DIR = "/Users/zhengyishen/Codes/claude-code/voice/models/coreml"
const val ASSETS_DIR = "/Users/zhengyishen/Codes/claude-code/voice/models/assets"
const val VAD_MODEL_PATH = "/Users/zhengyishen/Codes/claude-code/voice/models/coreml/silero-vad.mlmodelc"
const val ONNX_MODEL_DIR = "/Users/zhengyishen/Codes/claude-code/voice/models/onnx"
const val VOICE_LIBRARY_PATH = "/Users/zhengyishen/Codes/claude-code/voice/data/voice_library_xvector.json"
const val TEST_AUDIO_PATH = "/Users/zhengyishen/Codes/claude-code/voice/data/recordings/recording_20260112_002226.wav"
const val ALT_TEST_AUDIO_PATH = "/Users/zhengyishen/Codes/claude-code/voice/data/recordings/recording_20260111_235901.wav"

// Backend selection
enum class Backend { COREML, ONNX }
