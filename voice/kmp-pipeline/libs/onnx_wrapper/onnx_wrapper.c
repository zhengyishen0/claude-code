#include "onnx_wrapper.h"
#include "onnxruntime_c_api.h"
#include "coreml_provider_factory.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

// Enable CoreML Execution Provider for Neural Engine acceleration
#define USE_COREML_EP 1

// Global state
static const OrtApi* g_ort = NULL;
static OrtEnv* g_env = NULL;
static char g_error_msg[256] = {0};

// Session structure
struct OnnxSession {
    OrtSession* session;
    OrtSessionOptions* options;
    OrtAllocator* allocator;
    char** input_names;
    char** output_names;
    size_t num_inputs;
    size_t num_outputs;
};

static void set_error(const char* msg) {
    strncpy(g_error_msg, msg, sizeof(g_error_msg) - 1);
    g_error_msg[sizeof(g_error_msg) - 1] = '\0';
}

static void set_ort_error(OrtStatus* status) {
    if (status && g_ort) {
        const char* msg = g_ort->GetErrorMessage(status);
        set_error(msg ? msg : "Unknown ONNX error");
        g_ort->ReleaseStatus(status);
    }
}

int onnx_init(void) {
    if (g_ort != NULL) return 0;  // Already initialized

    g_ort = OrtGetApiBase()->GetApi(ORT_API_VERSION);
    if (!g_ort) {
        set_error("Failed to get ONNX Runtime API");
        return -1;
    }

    OrtStatus* status = g_ort->CreateEnv(ORT_LOGGING_LEVEL_WARNING, "voice_pipeline", &g_env);
    if (status) {
        set_ort_error(status);
        g_ort = NULL;
        return -1;
    }

    return 0;
}

void onnx_cleanup(void) {
    if (g_env && g_ort) {
        g_ort->ReleaseEnv(g_env);
    }
    g_env = NULL;
    g_ort = NULL;
}

OnnxSession* onnx_create_session(const char* model_path) {
    if (!g_ort || !g_env) {
        set_error("ONNX Runtime not initialized");
        return NULL;
    }

    OnnxSession* sess = (OnnxSession*)calloc(1, sizeof(OnnxSession));
    if (!sess) {
        set_error("Memory allocation failed");
        return NULL;
    }

    // Create session options
    OrtStatus* status = g_ort->CreateSessionOptions(&sess->options);
    if (status) {
        set_ort_error(status);
        free(sess);
        return NULL;
    }

    // Enable graph optimization (reduces load time on subsequent runs)
    g_ort->SetSessionGraphOptimizationLevel(sess->options, ORT_ENABLE_ALL);

    // Set thread count for CPU fallback
    g_ort->SetIntraOpNumThreads(sess->options, 4);
    g_ort->SetInterOpNumThreads(sess->options, 1);

#if USE_COREML_EP
    // Enable CoreML Execution Provider for Neural Engine acceleration
    // Flags: 0 = use all CoreML features including ANE
    status = OrtSessionOptionsAppendExecutionProvider_CoreML(sess->options, 0);
    if (status) {
        // CoreML EP failed - continue with CPU (non-fatal)
        printf("Warning: CoreML EP not available, using CPU: %s\n",
               g_ort->GetErrorMessage(status));
        g_ort->ReleaseStatus(status);
        status = NULL;
    }
#endif

    // Create session
    status = g_ort->CreateSession(g_env, model_path, sess->options, &sess->session);
    if (status) {
        set_ort_error(status);
        g_ort->ReleaseSessionOptions(sess->options);
        free(sess);
        return NULL;
    }

    // Get allocator
    status = g_ort->GetAllocatorWithDefaultOptions(&sess->allocator);
    if (status) {
        set_ort_error(status);
        g_ort->ReleaseSession(sess->session);
        g_ort->ReleaseSessionOptions(sess->options);
        free(sess);
        return NULL;
    }

    // Get input/output info
    g_ort->SessionGetInputCount(sess->session, &sess->num_inputs);
    g_ort->SessionGetOutputCount(sess->session, &sess->num_outputs);

    sess->input_names = (char**)calloc(sess->num_inputs, sizeof(char*));
    sess->output_names = (char**)calloc(sess->num_outputs, sizeof(char*));

    for (size_t i = 0; i < sess->num_inputs; i++) {
        g_ort->SessionGetInputName(sess->session, i, sess->allocator, &sess->input_names[i]);
    }
    for (size_t i = 0; i < sess->num_outputs; i++) {
        g_ort->SessionGetOutputName(sess->session, i, sess->allocator, &sess->output_names[i]);
    }

    return sess;
}

void onnx_destroy_session(OnnxSession* session) {
    if (!session) return;

    if (session->input_names) {
        for (size_t i = 0; i < session->num_inputs; i++) {
            if (session->input_names[i] && session->allocator) {
                session->allocator->Free(session->allocator, session->input_names[i]);
            }
        }
        free(session->input_names);
    }

    if (session->output_names) {
        for (size_t i = 0; i < session->num_outputs; i++) {
            if (session->output_names[i] && session->allocator) {
                session->allocator->Free(session->allocator, session->output_names[i]);
            }
        }
        free(session->output_names);
    }

    if (session->session && g_ort) {
        g_ort->ReleaseSession(session->session);
    }
    if (session->options && g_ort) {
        g_ort->ReleaseSessionOptions(session->options);
    }

    free(session);
}

int onnx_run_vad(
    OnnxSession* session,
    const float* audio, int audio_len,
    const float* h_in, const float* c_in,
    float* prob_out,
    float* h_out, float* c_out
) {
    if (!session || !g_ort) {
        set_error("Invalid session");
        return -1;
    }

    OrtMemoryInfo* memory_info = NULL;
    OrtStatus* status = g_ort->CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, &memory_info);
    if (status) {
        set_ort_error(status);
        return -1;
    }

    // Silero VAD ONNX has inputs: input, state, sr
    // state is combined (2, 1, 128) - h and c concatenated
    OrtValue* input_tensors[3] = {NULL, NULL, NULL};

    // Audio input: (1, audio_len)
    int64_t audio_shape[] = {1, audio_len};
    status = g_ort->CreateTensorWithDataAsOrtValue(
        memory_info, (void*)audio, audio_len * sizeof(float),
        audio_shape, 2, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &input_tensors[0]
    );
    if (status) { set_ort_error(status); goto cleanup; }

    // Combined state: (2, 1, 128) - stack h_in and c_in
    float* combined_state = (float*)malloc(256 * sizeof(float));
    memcpy(combined_state, h_in, 128 * sizeof(float));
    memcpy(combined_state + 128, c_in, 128 * sizeof(float));

    int64_t state_shape[] = {2, 1, 128};
    status = g_ort->CreateTensorWithDataAsOrtValue(
        memory_info, combined_state, 256 * sizeof(float),
        state_shape, 3, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &input_tensors[1]
    );
    if (status) { free(combined_state); set_ort_error(status); goto cleanup; }

    // Sample rate: scalar int64 (shape [])
    int64_t sr = 16000;
    status = g_ort->CreateTensorWithDataAsOrtValue(
        memory_info, &sr, sizeof(int64_t),
        NULL, 0, ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64, &input_tensors[2]
    );
    if (status) { free(combined_state); set_ort_error(status); goto cleanup; }

    // Input/output names for Silero VAD ONNX
    const char* input_names[] = {"input", "state", "sr"};
    const char* output_names[] = {"output", "stateN"};

    // Output tensors
    OrtValue* output_tensors[2] = {NULL, NULL};

    // Run inference
    status = g_ort->Run(
        session->session, NULL,
        input_names, (const OrtValue* const*)input_tensors, 3,
        output_names, 2, output_tensors
    );
    if (status) { free(combined_state); set_ort_error(status); goto cleanup; }

    // Extract outputs
    float* prob_data = NULL;
    g_ort->GetTensorMutableData(output_tensors[0], (void**)&prob_data);
    if (prob_data && prob_out) *prob_out = prob_data[0];

    // State output is (2, 1, 128) - split back to h and c
    float* state_data = NULL;
    g_ort->GetTensorMutableData(output_tensors[1], (void**)&state_data);
    if (state_data) {
        if (h_out) memcpy(h_out, state_data, 128 * sizeof(float));
        if (c_out) memcpy(c_out, state_data + 128, 128 * sizeof(float));
    }

    // Cleanup outputs
    for (int i = 0; i < 2; i++) {
        if (output_tensors[i]) g_ort->ReleaseValue(output_tensors[i]);
    }

    free(combined_state);

cleanup:
    for (int i = 0; i < 3; i++) {
        if (input_tensors[i]) g_ort->ReleaseValue(input_tensors[i]);
    }
    if (memory_info) g_ort->ReleaseMemoryInfo(memory_info);

    return status ? -1 : 0;
}

int onnx_run_asr(
    OnnxSession* session,
    const float* mel_lfr, int frames, int features,
    float* logits_out, int max_output_size
) {
    if (!session || !g_ort) {
        set_error("Invalid session");
        return -1;
    }

    OrtMemoryInfo* memory_info = NULL;
    OrtStatus* status = g_ort->CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, &memory_info);
    if (status) {
        set_ort_error(status);
        return -1;
    }

    // Input tensor: (1, frames, features)
    OrtValue* input_tensor = NULL;
    int64_t input_shape[] = {1, frames, features};
    status = g_ort->CreateTensorWithDataAsOrtValue(
        memory_info, (void*)mel_lfr, frames * features * sizeof(float),
        input_shape, 3, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &input_tensor
    );
    if (status) {
        set_ort_error(status);
        g_ort->ReleaseMemoryInfo(memory_info);
        return -1;
    }

    // Use first input/output name from session
    const char* input_names[] = {session->input_names[0]};
    const char* output_names[] = {session->output_names[0]};

    OrtValue* output_tensor = NULL;
    status = g_ort->Run(
        session->session, NULL,
        input_names, (const OrtValue* const*)&input_tensor, 1,
        output_names, 1, &output_tensor
    );

    int result = -1;
    if (!status && output_tensor) {
        // Get output shape
        OrtTensorTypeAndShapeInfo* type_info = NULL;
        g_ort->GetTensorTypeAndShape(output_tensor, &type_info);

        size_t dim_count = 0;
        g_ort->GetDimensionsCount(type_info, &dim_count);

        int64_t* dims = (int64_t*)malloc(dim_count * sizeof(int64_t));
        g_ort->GetDimensions(type_info, dims, dim_count);

        size_t output_size = 1;
        for (size_t i = 0; i < dim_count; i++) {
            output_size *= dims[i];
        }
        free(dims);
        g_ort->ReleaseTensorTypeAndShapeInfo(type_info);

        if ((int)output_size <= max_output_size) {
            float* output_data = NULL;
            g_ort->GetTensorMutableData(output_tensor, (void**)&output_data);
            if (output_data && logits_out) {
                memcpy(logits_out, output_data, output_size * sizeof(float));
            }
            result = (int)output_size;
        } else {
            set_error("Output buffer too small");
        }

        g_ort->ReleaseValue(output_tensor);
    } else if (status) {
        set_ort_error(status);
    }

    g_ort->ReleaseValue(input_tensor);
    g_ort->ReleaseMemoryInfo(memory_info);

    return result;
}

int onnx_run_speaker(
    OnnxSession* session,
    const float* fbank, int frames,
    float* embedding_out
) {
    if (!session || !g_ort) {
        set_error("Invalid session");
        return -1;
    }

    OrtMemoryInfo* memory_info = NULL;
    OrtStatus* status = g_ort->CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, &memory_info);
    if (status) {
        set_ort_error(status);
        return -1;
    }

    // Input tensor: (1, frames, 24)
    OrtValue* input_tensor = NULL;
    int64_t input_shape[] = {1, frames, 24};
    status = g_ort->CreateTensorWithDataAsOrtValue(
        memory_info, (void*)fbank, frames * 24 * sizeof(float),
        input_shape, 3, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &input_tensor
    );
    if (status) {
        set_ort_error(status);
        g_ort->ReleaseMemoryInfo(memory_info);
        return -1;
    }

    // Use first input/output name
    const char* input_names[] = {session->input_names[0]};
    const char* output_names[] = {session->output_names[0]};

    OrtValue* output_tensor = NULL;
    status = g_ort->Run(
        session->session, NULL,
        input_names, (const OrtValue* const*)&input_tensor, 1,
        output_names, 1, &output_tensor
    );

    int result = -1;
    if (!status && output_tensor) {
        float* output_data = NULL;
        g_ort->GetTensorMutableData(output_tensor, (void**)&output_data);
        if (output_data && embedding_out) {
            // Output is (1, 1, 512), copy 512 floats
            memcpy(embedding_out, output_data, 512 * sizeof(float));
            result = 0;
        }
        g_ort->ReleaseValue(output_tensor);
    } else if (status) {
        set_ort_error(status);
    }

    g_ort->ReleaseValue(input_tensor);
    g_ort->ReleaseMemoryInfo(memory_info);

    return result;
}

const char* onnx_get_error(void) {
    return g_error_msg;
}
