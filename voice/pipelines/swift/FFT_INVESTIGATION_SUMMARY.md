# FFT Investigation Summary

## Problem Statement

Swift pipeline for SenseVoice ASR is **18,833x slower than Python** due to FFT computation.
- Python FFT: ~4.4ms
- Swift manual DFT: ~82,865ms (95% of total pipeline time)

## What Was Done

### 1. Identified FFT as the Sole Bottleneck
- Created stage-by-stage unit tests comparing Swift vs Python
- Proved all other components (mel filterbank, log, LFR, CoreML) work correctly
- Isolated FFT as the only problematic component

### 2. Attempted vDSP FFT (Apple's Native Solution)

#### Simple Test (N=8) - SUCCESS
- Created `simple_vdsp_test.swift` with input [0,1,2,3,4,5,6,7]
- Discovered vDSP returns exactly **2x** the mathematical DFT values
- All frequency bins showed perfect 2.0 ratio
- 0.5 scaling produces exact match

#### Real Audio Test (N=400) - FAILURE
- Applied same approach to real audio frames
- Got scrambled output with inconsistent ratios (0.38x to 12.3x)
- Scaling by 0.5 did NOT fix it

### 3. Root Cause Discovery

**N=400 is NOT a power of 2!**

```
log2(400) = 8.643 → truncates to 8
vDSP configures for 2^8 = 256 elements, not 400
```

- vDSP_fft_zrip: Requires power-of-2 sizes only
- vDSP_DFT: Requires 3 × 5 × 2^n factorizations
- N=400 = 2^4 × 5^2 doesn't satisfy either constraint

### 4. Tested Zero-Padding to 512

- Padded 400 samples to 512 (next power of 2)
- DC bin matched perfectly, but other bins wrong
- Zero-padding interpolates in frequency domain → different values
- Cannot match Python's direct 400-point FFT

### 5. Explored Alternative Solutions

#### Option A: External FFT Libraries
- **KissFFT**: Swift package from AudioKit, supports arbitrary sizes
- **PFFFT**: Fast, permissive license, arbitrary sizes
- Status: Not yet tested

#### Option B: Find Power-of-2 SenseVoice Model
- Searched for SenseVoice pretrained with n_fft=512
- Found that some implementations DO use n_fft=512 by default
- Would require model conversion and validation

#### Option C: Python FFT from Swift (PythonKit)
- Technically possible but adds ~100MB runtime dependency
- Defeats purpose of native Swift pipeline
- Last resort only

## What Failed

| Attempt | Result | Why |
|---------|--------|-----|
| vDSP_fft_zrip with N=400 | Scrambled output | N=400 not power of 2 |
| vDSP_ctoz packing | Same scrambled output | Same root cause |
| vDSP_DFT_zrop_CreateSetup | Returns nil | N=400 not supported |
| Zero-padding to 512 | Different values | Changes frequency resolution |
| Manual even/odd packing | Same as vDSP_ctoz | Not the issue |
| Various scaling factors (0.5, 2.0) | Inconsistent | Root cause is size mismatch |

## Key Learnings

1. **vDSP FFT requires power-of-2 sizes** - This is non-negotiable
2. **vDSP returns 2x mathematical values** - Need 0.5 scaling (when it works)
3. **Output format**: DC in realp[0], Nyquist in imagp[0], other bins in realp/imagp[1..N/2-1]
4. **Zero-padding changes semantics** - Can't just pad and expect same results
5. **Python's FFT is more flexible** - Supports arbitrary sizes via Bluestein/mixed-radix

## Recommended Next Steps

### Priority 1: Test KissFFT (Highest Probability of Success)
```bash
# Add to Package.swift
.package(url: "https://github.com/AudioKit/KissFFT", from: "1.0.0")
```
- Supports arbitrary sizes including N=400
- Already has Swift bindings
- Used in production by AudioKit

### Priority 2: Check SenseVoice n_fft Configuration
- Some implementations use n_fft=512 by default
- If we can find/convert such a model, vDSP would work natively
- Check FunASR source for configurable n_fft

### Priority 3: Implement Bluestein's Algorithm
- Can compute arbitrary-size FFT using power-of-2 FFTs
- More complex but keeps native vDSP for core computation
- Fallback if external libraries don't perform well

## Files Created During Investigation

```
Sources/
├── simple_vdsp_test.swift      # N=8 test (WORKS)
├── understand_vdsp_fft.swift   # Deep dive into vDSP behavior
├── test_fix.swift              # Attempted fix for N=400
├── test_vdsp_ctoz.swift        # vDSP_ctoz approach
├── test_vdsp_padded.swift      # Zero-padding approach
├── test_vdsp_dft.swift         # vDSP_DFT attempt
├── debug_real_fft.swift        # Comprehensive comparison
└── profile_performance.swift   # Performance benchmarking
```

## Performance Target

| Metric | Current | Target | Gap |
|--------|---------|--------|-----|
| FFT time | 82,865ms | ~5ms | 16,573x |
| Total pipeline | 87,260ms | ~50ms | 1,745x |
| Real-time factor | 3,150x | <1x | Need 3,150x improvement |

## Conclusion

The vDSP approach cannot work for N=400 without fundamental changes. The most pragmatic solution is to integrate KissFFT or PFFFT, which support arbitrary FFT sizes and should provide significant speedup over the current O(N²) manual DFT implementation.
