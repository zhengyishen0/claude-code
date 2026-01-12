package com.voice.pipeline

// Audio configuration
const val SAMPLE_RATE = 16000
const val SAMPLE_RATE_DOUBLE = 16000.0
const val CHUNK_SIZE = 512          // 32ms audio callback at 16kHz

// VAD (Silero) configuration
const val VAD_CHUNK_SIZE = 4096     // 256ms at 16kHz
const val VAD_CONTEXT_SIZE = 64     // Context samples carried between chunks
const val VAD_STATE_SIZE = 128      // LSTM hidden/cell state size
const val VAD_MODEL_INPUT_SIZE = 4160  // VAD_CONTEXT_SIZE + VAD_CHUNK_SIZE
const val VAD_SPEECH_THRESHOLD = 0.5f
const val MIN_SPEECH_DURATION = 0.3  // seconds
const val MIN_SILENCE_DURATION = 0.3 // seconds

// Mel spectrogram configuration
const val N_MELS = 80               // Number of mel bands
const val N_FFT = 400               // 25ms window at 16kHz
const val HOP_LENGTH = 160          // 10ms hop at 16kHz

// LFR (Low Frame Rate) transform
const val LFR_M = 7                 // Stack 7 frames
const val LFR_N = 6                 // Skip 6 frames
const val FIXED_FRAMES = 500        // Padded output frames
const val FEATURE_DIM = N_MELS * LFR_M  // 560 dimensions

// Speaker embedding configuration
const val XVECTOR_SAMPLES = 48000   // 3 seconds at 16kHz
const val XVECTOR_DIM = 512         // Embedding dimension

// Speaker matching thresholds
const val BOUNDARY_THRESHOLD = 0.35f
const val CORE_THRESHOLD = 0.45f
const val AUTO_LEARN_THRESHOLD = 0.55f
const val CONFLICT_MARGIN = 0.1f

// Speaker profile limits
const val MAX_CORE = 5              // Max core embeddings per speaker
const val MAX_BOUNDARY = 10         // Max boundary embeddings per speaker
const val MIN_DIVERSITY = 0.1f      // Minimum distance to add new embedding
