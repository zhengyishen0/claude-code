# Swift Voice Pipeline - Handoff Summary

**Date**: 2026-01-11
**Purpose**: Migrate Python SenseVoice ASR pipeline to native Swift for macOS app "YouPu"

---

## Current Status: ✅ WORKING

The Swift pipeline now produces **correct output** and runs at **acceptable speed**.

---

## What Was Built

### Swift Pipeline (`Sources/main.swift`)
Complete audio-to-text pipeline matching Python's torchaudio implementation:

```
Audio File (WAV)
    ↓
1. Load & Resample to 16kHz
    ↓
2. Center Padding (reflect mode, n_fft/2 on each side)
    ↓
3. Frame Extraction (400 samples, hop=160)
    ↓
4. Hamming Window
    ↓
5. FFT → Magnitude Spectrum (KissFFT, 201 bins)
    ↓
6. Mel Filterbank (80 mels, loaded from torchaudio export)
    ↓
7. Log Transform: log(max(x, 1e-10))
    ↓
8. LFR (stack 7 frames, skip 6) → 560-dim features
    ↓
9. Pad to 500 frames
    ↓
10. CoreML Inference (sensevoice-500-itn.mlmodelc)
    ↓
11. CTC Greedy Decoding
    ↓
Token IDs (ready for SentencePiece decoding)
```

---

## Key Achievement: FFT Problem Solved

### The Problem
- **vDSP (Apple's native FFT) doesn't support N=400** (not power of 2)
- Manual O(N²) DFT was 18,833x slower than Python
- vDSP only supports: power-of-2 (FFT) or 3×5×2^n (DFT)
- N=400 = 2^4 × 5^2 doesn't fit either pattern

### The Solution
- Integrated **KissFFT** library (supports arbitrary sizes)
- Added to Package.swift: `https://github.com/AudioKit/KissFFT.git`

### Results

| Metric | Before (Manual DFT) | After (KissFFT) |
|--------|---------------------|-----------------|
| Mel Spectrogram | 82,865ms | **646ms** |
| Speedup | - | **128x faster** |
| Accuracy | ✅ Matches Python | ✅ Matches Python |

---

## Current Performance (27.7s audio)

| Stage | Swift Time | Notes |
|-------|------------|-------|
| Audio Load + Resample | ~50ms | |
| Mel Spectrogram (with FFT) | **646ms** | Was 82,865ms before KissFFT |
| LFR Transform | 2ms | |
| CoreML Inference | 3,933ms | Model computation |
| CTC Decoding | <1ms | |
| **Total** | **~4,600ms** | **6x faster than real-time** |

---

## Files in This Directory

| File | Purpose |
|------|---------|
| `Sources/main.swift` | Complete Swift pipeline |
| `Package.swift` | Swift package with KissFFT dependency |
| `mel_filterbank.bin` | Torchaudio mel filterbank (80 mels × 201 bins) |
| `python_features.bin` | Reference features for accuracy testing |
| `benchmark_python.py` | Python benchmark script |
| `FFT_INVESTIGATION_SUMMARY.md` | Detailed FFT research notes |
| `.gitignore` | Excludes .build/, *.bin |

---

## Accuracy Verification

### FFT Output (First 5 Bins)
```
Python:  [0.1606377, 0.2258404, 0.6836231, 0.0363915, 0.1338275]
Swift:   [0.1606377, 0.2258404, 0.6836232, 0.0363915, 0.1338275]
         ✅ MATCH (within floating point tolerance)
```

### Final Output
- **Token count**: 56 tokens (identical Python vs Swift)
- **Token IDs**: Identical sequence

---

## What's NOT Done Yet

### 1. SentencePiece Decoding
- Token IDs are produced but not decoded to text
- Need to integrate SentencePiece library or implement BPE decoder
- Tokenizer file: `chn_jpn_yue_eng_ko_spectok.bpe.model`

### 2. Detailed Speed Comparison
- Need side-by-side benchmark of each pipeline stage
- Python benchmark script exists (`benchmark_python.py`)
- Swift timing is logged but not in comparable format

### 3. Integration with YouPu App
- Pipeline works standalone
- Not yet integrated into the macOS app

---

## Known Issues

### 1. Absolute Paths
Some paths in `main.swift` are hardcoded:
- Model path
- Test audio path
- Python features path

Should be made relative or configurable for production.

### 2. CoreML Stride Bug (FIXED)
MLMultiArray had stride 25056 instead of 25055. Fixed by using explicit stride calculation:
```swift
let index = batch * stride0 + time * stride1 + vocab * stride2
```

### 3. No CMVN Normalization
Python doesn't use CMVN - confirmed and matched in Swift. Don't add it.

---

## How to Run

```bash
cd /Users/zhengyishen/Codes/claude-code-voice-isolation/voice/swift-pipeline-test

# Build
swift build

# Run
swift run
```

### Expected Output
```
✅ Loaded Python features: (500, 560)
...
✅ Mel shape: (2771, 80)
⏱️ Time: 646.3ms
...
✅ Tokens: [24885, 25004, 24993, ...]
   Total tokens: 56
```

---

## Dependencies

### Swift Package
- **KissFFT** 1.0.0 - `https://github.com/AudioKit/KissFFT.git`

### External Files Required
- `mel_filterbank.bin` - Export from torchaudio (included)
- `sensevoice-500-itn.mlmodelc` - CoreML model (in YouPu app)
- `chn_jpn_yue_eng_ko_spectok.bpe.model` - Tokenizer (in YouPu app)

---

## Next Steps for New Agent

1. **Run detailed Python vs Swift benchmark**
   - Use `benchmark_python.py` as starting point
   - Add equivalent timing to Swift
   - Compare each stage

2. **Implement SentencePiece decoding**
   - Either integrate SPM library or implement BPE manually
   - Decode token IDs to actual text

3. **Integrate into YouPu app**
   - Move pipeline code into app
   - Handle audio input from microphone
   - Display transcription results

---

## Reference Links

- [KissFFT GitHub](https://github.com/AudioKit/KissFFT)
- [SenseVoice GitHub](https://github.com/FunAudioLLM/SenseVoice)
- [Apple vDSP FFT Docs](https://developer.apple.com/documentation/accelerate/vdsp/fft)
