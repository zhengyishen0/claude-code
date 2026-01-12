#ifndef ONNX_WRAPPER_H
#define ONNX_WRAPPER_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Opaque handle types
typedef struct OnnxSession OnnxSession;

// Initialize ONNX Runtime (call once at startup)
int onnx_init(void);

// Cleanup ONNX Runtime (call at shutdown)
void onnx_cleanup(void);

// Create a session from model file
OnnxSession* onnx_create_session(const char* model_path);

// Destroy a session
void onnx_destroy_session(OnnxSession* session);

// Run VAD inference
// Input: audio (4160 floats), h_in (128 floats), c_in (128 floats)
// Output: probability, h_out (128 floats), c_out (128 floats)
// Returns 0 on success, -1 on error
int onnx_run_vad(
    OnnxSession* session,
    const float* audio, int audio_len,
    const float* h_in, const float* c_in,
    float* prob_out,
    float* h_out, float* c_out
);

// Run ASR inference
// Input: mel_lfr (frames x features floats)
// Output: logits (frames x vocab_size floats)
// Returns output size on success, -1 on error
int onnx_run_asr(
    OnnxSession* session,
    const float* mel_lfr, int frames, int features,
    float* logits_out, int max_output_size
);

// Run speaker embedding inference
// Input: fbank (frames x 24 floats)
// Output: embedding (512 floats)
// Returns 0 on success, -1 on error
int onnx_run_speaker(
    OnnxSession* session,
    const float* fbank, int frames,
    float* embedding_out
);

// Get last error message
const char* onnx_get_error(void);

#ifdef __cplusplus
}
#endif

#endif // ONNX_WRAPPER_H
