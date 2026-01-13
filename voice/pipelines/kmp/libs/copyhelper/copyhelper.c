#include "copyhelper.h"
#include <string.h>

void copy_floats(const float* src, float* dst, size_t count) {
    memcpy(dst, src, count * sizeof(float));
}

void copy_mlarray_to_floats(const void* src, float* dst, size_t count) {
    memcpy(dst, src, count * sizeof(float));
}

void copy_floats_to_mlarray(const float* src, void* dst, size_t count) {
    memcpy(dst, src, count * sizeof(float));
}

void copy_strided_to_contiguous(const float* src, float* dst, size_t count, size_t stride) {
    for (size_t i = 0; i < count; i++) {
        dst[i] = src[i * stride];
    }
}

size_t copy_2d_output(const void* src, float* dst, size_t time, size_t vocab, size_t stride1) {
    const float* srcPtr = (const float*)src;

    // If stride1 == vocab, data is contiguous - use single memcpy
    if (stride1 == vocab) {
        memcpy(dst, src, time * vocab * sizeof(float));
    } else {
        // Non-contiguous: copy each time step separately
        for (size_t t = 0; t < time; t++) {
            memcpy(dst + t * vocab, srcPtr + t * stride1, vocab * sizeof(float));
        }
    }

    return time * vocab;
}
