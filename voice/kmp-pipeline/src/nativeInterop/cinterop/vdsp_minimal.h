// Minimal vDSP header for KMP cinterop
// Only includes the functions needed for audio processing, avoiding problematic Sparse headers

#ifndef VDSP_MINIMAL_H
#define VDSP_MINIMAL_H

#include <stddef.h>

// Basic types
typedef float vDSP_Length;
typedef long vDSP_Stride;

// FFT setup types
typedef struct OpaqueFFTSetup* FFTSetup;
typedef struct OpaqueFFTSetupD* FFTSetupD;

// Complex split types
typedef struct DSPSplitComplex {
    float* realp;
    float* imagp;
} DSPSplitComplex;

typedef struct DSPDoubleSplitComplex {
    double* realp;
    double* imagp;
} DSPDoubleSplitComplex;

// FFT radix options
typedef int FFTRadix;
#define kFFTRadix2 0
#define kFFTRadix3 1
#define kFFTRadix5 2

// FFT direction
typedef int FFTDirection;
#define kFFTDirection_Forward 1
#define kFFTDirection_Inverse -1

#ifdef __cplusplus
extern "C" {
#endif

// FFT setup functions
extern FFTSetup vDSP_create_fftsetup(vDSP_Length __Log2n, FFTRadix __Radix);
extern void vDSP_destroy_fftsetup(FFTSetup __Setup);

// FFT functions
extern void vDSP_fft_zrip(FFTSetup __Setup, const DSPSplitComplex* __C, vDSP_Stride __IC, vDSP_Length __Log2N, FFTDirection __Direction);

// Vector operations
extern void vDSP_vsmul(const float* __A, vDSP_Stride __IA, const float* __B, float* __C, vDSP_Stride __IC, vDSP_Length __N);
extern void vDSP_vsma(const float* __A, vDSP_Stride __IA, const float* __B, const float* __C, vDSP_Stride __IC, float* __D, vDSP_Stride __ID, vDSP_Length __N);
extern void vDSP_vadd(const float* __A, vDSP_Stride __IA, const float* __B, vDSP_Stride __IB, float* __C, vDSP_Stride __IC, vDSP_Length __N);
extern void vDSP_vmul(const float* __A, vDSP_Stride __IA, const float* __B, vDSP_Stride __IB, float* __C, vDSP_Stride __IC, vDSP_Length __N);
extern void vDSP_vdiv(const float* __B, vDSP_Stride __IB, const float* __A, vDSP_Stride __IA, float* __C, vDSP_Stride __IC, vDSP_Length __N);
extern void vDSP_vsq(const float* __A, vDSP_Stride __IA, float* __C, vDSP_Stride __IC, vDSP_Length __N);
extern void vDSP_vclr(float* __C, vDSP_Stride __IC, vDSP_Length __N);
extern void vDSP_vfill(const float* __A, float* __C, vDSP_Stride __IC, vDSP_Length __N);
extern void vDSP_mmov(const float* __A, float* __C, vDSP_Length __M, vDSP_Length __N, vDSP_Length __TA, vDSP_Length __TC);

// Complex magnitude
extern void vDSP_zvabs(const DSPSplitComplex* __A, vDSP_Stride __IA, float* __C, vDSP_Stride __IC, vDSP_Length __N);
extern void vDSP_zvmags(const DSPSplitComplex* __A, vDSP_Stride __IA, float* __C, vDSP_Stride __IC, vDSP_Length __N);

// Convert between complex formats
extern void vDSP_ctoz(const float* __C, vDSP_Stride __IC, const DSPSplitComplex* __Z, vDSP_Stride __IZ, vDSP_Length __N);
extern void vDSP_ztoc(const DSPSplitComplex* __Z, vDSP_Stride __IZ, float* __C, vDSP_Stride __IC, vDSP_Length __N);

// Log/exp functions
extern void vvlogf(float* __y, const float* __x, const int* __n);
extern void vvlog10f(float* __y, const float* __x, const int* __n);
extern void vvexpf(float* __y, const float* __x, const int* __n);

// Vector max/min
extern void vDSP_maxv(const float* __A, vDSP_Stride __IA, float* __C, vDSP_Length __N);
extern void vDSP_minv(const float* __A, vDSP_Stride __IA, float* __C, vDSP_Length __N);
extern void vDSP_maxvi(const float* __A, vDSP_Stride __IA, float* __C, vDSP_Length* __I, vDSP_Length __N);

// Mean and sum
extern void vDSP_meanv(const float* __A, vDSP_Stride __IA, float* __C, vDSP_Length __N);
extern void vDSP_sve(const float* __A, vDSP_Stride __IA, float* __C, vDSP_Length __N);
extern void vDSP_svesq(const float* __A, vDSP_Stride __IA, float* __C, vDSP_Length __N);

// Dot product
extern void vDSP_dotpr(const float* __A, vDSP_Stride __IA, const float* __B, vDSP_Stride __IB, float* __C, vDSP_Length __N);

// Vector scaling and offset
extern void vDSP_vsmsa(const float* __A, vDSP_Stride __IA, const float* __B, const float* __C, float* __D, vDSP_Stride __ID, vDSP_Length __N);

// Hann window
extern void vDSP_hann_window(float* __C, vDSP_Length __N, int __Flag);
#define vDSP_HANN_NORM 0
#define vDSP_HANN_DENORM 2

#ifdef __cplusplus
}
#endif

#endif // VDSP_MINIMAL_H
