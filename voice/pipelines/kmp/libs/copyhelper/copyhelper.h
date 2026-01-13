#ifndef COPYHELPER_H
#define COPYHELPER_H

#include <stddef.h>

/**
 * Bulk copy float array from source to destination
 * Uses memcpy for maximum performance
 */
void copy_floats(const float* src, float* dst, size_t count);

/**
 * Bulk copy from void pointer (MLMultiArray.dataPointer) to float array
 * Handles the common case of extracting data from CoreML output
 */
void copy_mlarray_to_floats(const void* src, float* dst, size_t count);

/**
 * Bulk copy from float array to void pointer (MLMultiArray.dataPointer)
 * Handles the common case of setting CoreML input data
 */
void copy_floats_to_mlarray(const float* src, void* dst, size_t count);

/**
 * Copy with stride - for non-contiguous MLMultiArray data
 * Copies 'count' floats from src with given stride to contiguous dst
 */
void copy_strided_to_contiguous(const float* src, float* dst, size_t count, size_t stride);

/**
 * Bulk copy for 2D tensor output [time, vocab]
 * Optimized for the ASR logits case: copies entire output in one pass
 * Returns total floats copied (time * vocab)
 */
size_t copy_2d_output(const void* src, float* dst, size_t time, size_t vocab, size_t stride1);

#endif /* COPYHELPER_H */
