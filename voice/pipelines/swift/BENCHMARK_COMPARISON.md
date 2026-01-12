# Python vs Swift Pipeline Benchmark Comparison

**Date**: 2026-01-11
**Audio**: test_recording.wav (27.7s, 443,336 samples @ 16kHz)

---

## Executive Summary

| Metric | Python | Swift | Notes |
|--------|--------|-------|-------|
| **Total Time** | 23.5ms | 3,192ms | Python is preprocessing only |
| **With CoreML** | ~3,700ms | 3,192ms | Including inference |
| **Accuracy** | Baseline | Identical | 56 tokens match exactly |
| **Real-time Factor** | ~0.13x | ~0.12x | Both faster than real-time |

---

## Stage-by-Stage Timing Comparison

### Preprocessing Stages

| Stage | Python (ms) | Swift (ms) | Ratio | Notes |
|-------|-------------|------------|-------|-------|
| **Audio Load** | 9.68 | - | - | Swift includes in Mel stage |
| **Mel Spectrogram** | 12.21 | 516.1 | 42x | Swift includes FFT, Mel, Log |
| **Log Transform** | 0.79 | (included) | - | Included in Swift Mel stage |
| **LFR Transform** | 0.62 | 1.8 | 3x | Very fast in both |
| **Padding** | 0.17 | <1 | - | Negligible |
| **Preprocessing Total** | 23.48 | ~518 | 22x | |

### Inference Stages

| Stage | Python (ms) | Swift (ms) | Notes |
|-------|-------------|------------|-------|
| **Model Load** | ~1,200 | 147 | Swift 8x faster (cached?) |
| **CoreML Inference** | ~2,500 | 2,674 | Similar performance |
| **CTC Decoding** | <5 | <1 | Negligible |

---

## Accuracy Verification

### Shapes Match

| Stage | Python | Swift | Match |
|-------|--------|-------|-------|
| Audio samples | 443,336 | 443,336 | Yes |
| Mel spectrogram | (2771, 80) | (2771, 80) | Yes |
| LFR features | (461, 560) | (461, 560) | Yes |
| Padded features | (500, 560) | (500, 560) | Yes |
| Output logits | (504, 25055) | (504, 25055) | Yes |
| **Token count** | **56** | **56** | **Yes** |

### Values Match

**Log-Mel First Frame (first 10 values):**
```
Python: [-3.018, -1.732, -1.024, -1.126, -3.402, -2.903, -2.501, -1.255, -2.533, -2.776]
Swift:  [-3.018, -1.732, -1.024, -1.126, -3.402, -2.903, -2.501, -1.255, -2.533, -2.776]
```

**FFT Magnitude (first 5 bins):**
```
Python: [0.1606377, 0.2258404, 0.6836231, 0.0363915, 0.1338275]
Swift:  [0.1606377, 0.2258404, 0.6836232, 0.0363915, 0.1338275]
         (differs by 1e-7 - floating point precision)
```

**Stats Match:**
```
              Python          Swift
min:         -10.732         -10.732
max:           3.158           3.158
mean:         -4.130          -4.130
```

**Token IDs (first 30):**
```
Python: [24885, 25004, 24993, 25016, 68, 5499, 124, 9691, 9697, 568, 13, 3, 228, 5499, 124, 9694, 8564, 4, 9688, 144, 295, 230, 11, 4657, 1552, 106, 12624, 19268, 12156, 13295]
Swift:  [24885, 25004, 24993, 25016, 68, 5499, 124, 9691, 9697, 568, 13, 3, 228, 5499, 124, 9694, 8564, 4, 9688, 144, 295, 230, 11, 4657, 1552, 106, 12624, 19268, 12156, 13295]
         IDENTICAL
```

---

## Analysis

### Why is Swift Mel Spectrogram Slower?

1. **Python uses optimized BLAS/LAPACK** through NumPy/PyTorch
2. **Swift KissFFT** is single-threaded, Python FFT is vectorized
3. **Python torchaudio** MelSpectrogram is heavily optimized C++ code
4. **Swift implementation** is pure Swift with manual loops

### Optimization Opportunities

| Opportunity | Potential Speedup | Effort |
|-------------|-------------------|--------|
| Use vDSP for Mel filterbank matmul | ~5-10x | Medium |
| Parallelize FFT frames with GCD | ~4x | Low |
| Use Metal for GPU FFT | ~20x | High |
| Pre-compile KissFFT with -O3 | ~2x | Low |

### Current Performance Assessment

For a **27.7 second audio file**:
- **Swift total**: 3.2 seconds (0.12x real-time)
- **Acceptable for**: Real-time transcription
- **Bottleneck**: CoreML inference (84% of time)

---

## Conclusion

The Swift pipeline is **production-ready** for the YouPu app:

1. **Accuracy**: Identical output to Python reference
2. **Speed**: Faster than real-time (0.12x)
3. **Bottleneck**: CoreML inference dominates (2.7s of 3.2s total)
4. **Preprocessing**: Could be optimized but not critical path

### Recommendation

Focus optimization efforts on:
1. **CoreML inference** - Try ANE (Apple Neural Engine) vs GPU
2. **Batch processing** - If processing multiple clips
3. **Streaming** - For real-time microphone input

Preprocessing optimization (Mel spectrogram) has diminishing returns since CoreML inference is 5x slower.

---

## Files Reference

| File | Purpose |
|------|---------|
| `compare_pipelines.py` | Python benchmark with JSON export |
| `benchmark_python.py` | Original Python benchmark |
| `Sources/main.swift` | Swift pipeline implementation |
| `comparison/python_results.json` | Python benchmark results |
| `HANDOFF_SUMMARY.md` | Complete project handoff docs |
