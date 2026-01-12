# Technical Comparison: Our Python vs Hex/FluidAudio Stack

## Critical Finding: Language Support

### Parakeet TDT v3 (FluidAudio's ASR)
**Supported Languages (25 European only):**
- English, German, French, Spanish, Italian, Portuguese
- Russian, Ukrainian, Polish, Czech, Slovak
- Dutch, Danish, Swedish, Finnish, Norwegian
- Greek, Bulgarian, Croatian, Romanian, Hungarian
- Estonian, Latvian, Lithuanian, Maltese, Slovenian

**❌ NO Chinese, Mandarin, or Cantonese support!**

### SenseVoice (Our Current ASR)
**Supported Languages:**
- ✅ Chinese (Mandarin)
- ✅ Cantonese
- ✅ English
- ✅ Japanese
- ✅ Korean

**Conclusion: We MUST keep SenseVoice for Chinese support.**

---

## Component-by-Component Comparison

### 1. Voice Activity Detection (VAD)

| Aspect | Our Python (Silero) | FluidAudio (Silero) |
|--------|---------------------|---------------------|
| Model | Silero VAD PyTorch | Silero VAD CoreML |
| Performance | ~1000x RT | ~1000x RT |
| Streaming | Custom VADProcessor | Built-in streaming |
| Accuracy | Same | Same |

**Verdict: ✅ Compatible - Same underlying model, FluidAudio has CoreML version**

### 2. Automatic Speech Recognition (ASR)

| Aspect | Our Python (SenseVoice) | FluidAudio (Parakeet) |
|--------|------------------------|----------------------|
| Chinese | ✅ Yes | ❌ No |
| English | ✅ Yes | ✅ Yes |
| Speed | ~25x RT | ~190x RT |
| Model Size | 448MB | 600MB |
| Format | CoreML | CoreML |

**Verdict: ❌ Cannot use FluidAudio's ASR - No Chinese support**

**Strategy: Keep SenseVoice, integrate separately**

### 3. Speaker Embeddings

| Aspect | Our Python (x-vector) | FluidAudio (WeSpeaker) |
|--------|----------------------|------------------------|
| Source | SpeechBrain | WeSpeaker toolkit |
| Architecture | TDNN x-vector | Multiple (ECAPA, ResNet, x-vector) |
| Dimensions | 512 | 192-512 (model dependent) |
| EER (VoxCeleb1) | ~1.0% | ~0.45-0.72% |
| Speed | ~14ms/5s | Similar |

**Verdict: ⚠️ WeSpeaker is newer and potentially better**

#### WeSpeaker Architecture Options
From [WeSpeaker GitHub](https://github.com/wenet-e2e/wespeaker):
1. **TDNN x-vector** - Same as our current approach
2. **ResNet-based r-vector** - Better accuracy (ResNet34, ResNet293)
3. **ECAPA-TDNN** - State-of-the-art (0.45% EER)

**Key Question: Can WeSpeaker replace x-vector for our use case?**
- Both produce embeddings for cosine similarity matching ✅
- WeSpeaker has better benchmark performance ✅
- Our self-improving profile logic works with any embedding ✅

### 4. Speaker Diarization / Identification

| Aspect | Our Python | FluidAudio (Pyannote) |
|--------|------------|----------------------|
| Approach | Custom two-layer profiles | Clustering-based |
| Self-improving | ✅ Yes (auto-learn) | ❌ No |
| Enrollment | ✅ Yes | Limited |
| Cross-session | ✅ Yes | ⚠️ Requires custom work |

**Verdict: ❌ Pyannote doesn't support our self-improving profiles**

#### Key Difference in Approach

**Our Python (Identification-based):**
```
1. Detect speech segment
2. Extract embedding
3. Match against ENROLLED profiles
4. If match > threshold → known speaker
5. If high confidence → auto-learn
```

**Pyannote (Clustering-based):**
```
1. Detect all speech segments
2. Extract embeddings for all
3. Cluster embeddings into groups
4. Label groups as "Speaker 1", "Speaker 2"
5. No persistent identity across sessions
```

**Our self-improving profile system is NOT compatible with Pyannote's clustering approach.**

---

## Refactoring Strategy

### What We Can Use from FluidAudio

| Component | Use FluidAudio? | Notes |
|-----------|-----------------|-------|
| VAD (Silero) | ✅ Yes | CoreML version, same model |
| ASR (Parakeet) | ❌ No | No Chinese support |
| Speaker Embeddings | ⚠️ Maybe | Test WeSpeaker vs x-vector |
| Diarization (Pyannote) | ❌ No | Doesn't fit our self-improving model |

### What We Must Build/Port

| Component | Source | Notes |
|-----------|--------|-------|
| ASR | SenseVoice CoreML | Already have it |
| Speaker Profiles | Port from Python | Two-layer, self-improving |
| Matching Logic | Port from Python | Two-phase algorithm |
| Auto-learning | Port from Python | σ-based classification |
| Voice Isolation | New Swift code | Already prototyped |

### What We Can Use from Hex

| Component | Use from Hex? | Notes |
|-----------|---------------|-------|
| Menu Bar UI | ✅ Yes | SwiftUI, well-designed |
| Hotkey System | ✅ Yes | Global hotkeys |
| App Structure | ✅ Yes | Swift Composable Architecture |
| Audio Capture | ⚠️ Partial | Need to add Voice Isolation |
| FluidAudio Integration | ⚠️ Partial | Only use VAD, not ASR |

---

## Revised Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Forked from Hex                              │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  UI Layer (SwiftUI + Composable Architecture)            │  │
│  │  - Menu bar interface                                     │  │
│  │  - Global hotkeys                                         │  │
│  │  - Settings panel                                         │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Audio Capture Layer                          │
│  ┌─────────────────────┐    ┌─────────────────────┐            │
│  │  Standard Capture   │    │  Voice Isolation    │            │
│  │  (AVAudioEngine)    │    │  (Voice Processing) │            │
│  └─────────────────────┘    └─────────────────────┘            │
│                    Our custom Swift code                        │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Processing Pipeline                          │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  VAD: FluidAudio (Silero CoreML)                         │   │
│  │  ✅ Use as-is                                            │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│                              ▼                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  ASR: SenseVoice CoreML                                  │   │
│  │  ❌ Cannot use FluidAudio (no Chinese)                   │   │
│  │  ✅ Port our existing CoreML model                       │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│                              ▼                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Speaker Embeddings: x-vector OR WeSpeaker               │   │
│  │  ⚠️ Need to test both for family voice distinction      │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│                              ▼                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Self-Improving Profiles: Port from Python               │   │
│  │  - Two-layer (core/boundary) architecture                │   │
│  │  - Two-phase matching                                    │   │
│  │  - Auto-learning with σ-based classification             │   │
│  │  ❌ Cannot use Pyannote (clustering, not identification) │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Decision Matrix

| Decision | Option A | Option B | Recommendation |
|----------|----------|----------|----------------|
| ASR Model | Parakeet (FluidAudio) | SenseVoice (our own) | **SenseVoice** (Chinese required) |
| Speaker Embeddings | x-vector (current) | WeSpeaker | **Test both** |
| VAD | Silero PyTorch | Silero CoreML (FluidAudio) | **FluidAudio** |
| Diarization | Pyannote | Our self-improving profiles | **Our profiles** |
| UI | Build from scratch | Fork Hex | **Fork Hex** |

---

## Model Conversion Requirements

### Already Have (CoreML)
- ✅ SenseVoice (448MB)
- ✅ SepReformer (80MB)

### From FluidAudio (CoreML)
- ✅ Silero VAD (can use directly)

### Need to Convert
- ⚠️ x-vector → CoreML (if keeping x-vector)
- OR use WeSpeaker from FluidAudio

### WeSpeaker in FluidAudio
FluidAudio uses WeSpeaker for speaker embeddings. If we use FluidAudio's embedding extraction, we get CoreML-optimized WeSpeaker for free.

---

## Implementation Plan (Revised)

### Phase 1: Prototype (1 week)
1. Fork Hex
2. Test FluidAudio's WeSpeaker embeddings with family voices
3. Compare with our x-vector embeddings
4. Decision: Which embedding model to use

### Phase 2: Core Pipeline (2 weeks)
1. Integrate SenseVoice CoreML (replace Parakeet)
2. Use FluidAudio's Silero VAD
3. Port self-improving profile logic to Swift
4. Port two-phase matching algorithm

### Phase 3: Voice Isolation (1 week)
1. Add dual capture mode
2. Implement comparison metrics
3. A/B testing framework

### Phase 4: Polish (1 week)
1. UI refinements
2. Settings panel
3. Performance optimization

---

## Summary

**What to take from Hex/FluidAudio:**
- ✅ Hex's UI and app structure
- ✅ FluidAudio's Silero VAD (CoreML)
- ⚠️ FluidAudio's WeSpeaker (need to test)

**What we MUST keep from Python:**
- ✅ SenseVoice ASR (Chinese support)
- ✅ Two-layer self-improving profiles
- ✅ Two-phase matching algorithm
- ✅ Auto-learning logic

**What we cannot use from FluidAudio:**
- ❌ Parakeet ASR (no Chinese)
- ❌ Pyannote diarization (clustering, not identification)
