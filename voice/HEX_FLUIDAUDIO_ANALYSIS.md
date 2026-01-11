# Hex & FluidAudio Analysis

## Option 1: Fork Hex

### What Hex Provides

| Feature | Status | Notes |
|---------|--------|-------|
| Menu bar app | ✅ | Global hotkey, SwiftUI |
| Transcription | ✅ | Parakeet TDT v3 or WhisperKit |
| Architecture | ✅ | Swift Composable Architecture |
| License | ✅ | MIT (can fork freely) |
| Speaker ID | ❌ | Not implemented |
| Speaker Diarization | ❌ | Not implemented |
| Self-improving profiles | ❌ | Not implemented |
| Voice Isolation | ❌ | Not implemented |

### What We'd Need to Add
1. Speaker embedding extraction
2. Two-layer speaker profiles (core/boundary)
3. Two-phase matching algorithm
4. Auto-learning system
5. Voice Isolation toggle
6. Parallel comparison mode

### Pros
- Solid SwiftUI foundation
- Menu bar app already done
- Hotkey system implemented
- Integration with FluidAudio already exists

### Cons
- Need to learn Swift Composable Architecture
- Still need to build entire speaker ID system
- May have design decisions that conflict with our needs

---

## Option 2: Use FluidAudio Directly (New App)

### What FluidAudio Provides

| Feature | Status | Notes |
|---------|--------|-------|
| VAD | ✅ | Silero VAD (same as our Python!) |
| Transcription | ✅ | Parakeet TDT v3, ~190x RT on M4 |
| Speaker Diarization | ✅ | Pyannote pipeline |
| Speaker Embeddings | ✅ | WeSpeaker for voice comparison |
| Streaming Mode | ✅ | Real-time speaker labels |
| CoreML/ANE | ✅ | Optimized for Apple Silicon |

### Key Insight: FluidAudio Already Has Speaker Embeddings!

```swift
// FluidAudio provides speaker embedding extraction
// "Generate speaker embeddings for voice comparison and clustering"
```

This means we can use FluidAudio's embeddings for our self-improving profile system!

### What We'd Need to Build
1. Menu bar UI (SwiftUI - straightforward)
2. Two-layer speaker profile system (port from Python)
3. Two-phase matching algorithm (port from Python)
4. Auto-learning logic (port from Python)
5. Voice Isolation integration
6. Persistence layer (JSON/SQLite)

### Pros
- **All ML models included** - no conversion needed!
- Same VAD as Python (Silero)
- Speaker embeddings ready to use
- ~190x real-time (faster than our Python)
- Designed for streaming/real-time
- Clean slate - design exactly what we need

### Cons
- Build UI from scratch
- More initial work

---

## Option 3: Fork Hex + Use Full FluidAudio Stack

### Best of Both Worlds

```
Hex (UI Layer)
    │
    ├── Menu bar app ✅
    ├── Hotkey system ✅
    ├── SwiftUI components ✅
    │
    ▼
FluidAudio (ML Layer)
    │
    ├── VAD (Silero) ✅
    ├── ASR (Parakeet) ✅
    ├── Speaker Embeddings (WeSpeaker) ✅
    │
    ▼
Our Custom Layer
    │
    ├── Two-layer profiles (core/boundary)
    ├── Two-phase matching
    ├── Auto-learning
    ├── Voice Isolation comparison
    └── Metrics collection
```

### Implementation Plan

1. **Fork Hex** → Rename to "VoiceFlow" or similar
2. **Upgrade FluidAudio integration** → Use full diarization + embeddings
3. **Add speaker profile system** → Port Python logic
4. **Add Voice Isolation** → Parallel capture mode
5. **Add comparison metrics** → A/B testing framework

---

## Feature Comparison: Our Python vs FluidAudio

| Feature | Our Python | FluidAudio | Compatible? |
|---------|------------|------------|-------------|
| VAD | Silero PyTorch | Silero CoreML | ✅ Same model |
| ASR | SenseVoice CoreML | Parakeet CoreML | ⚠️ Different (Parakeet faster) |
| Speaker Embedding | x-vector (512-dim) | WeSpeaker | ⚠️ Different (need to test) |
| Separation | SepReformer | Not included | ❌ We'd need to add |
| Streaming | Custom VADProcessor | Built-in | ✅ FluidAudio better |

### Key Question: Can WeSpeaker Replace x-vector?

Both produce speaker embeddings for cosine similarity matching. We need to verify:
1. Embedding dimension (likely similar)
2. Quality for family voice distinction
3. Speed comparison

If WeSpeaker works well, we can use FluidAudio's full stack and just add our self-improving logic on top.

---

## Recommendation

### 🏆 Option 3: Fork Hex + Full FluidAudio

**Reasoning:**
1. Hex provides proven UI/UX patterns (menu bar, hotkeys)
2. FluidAudio provides all ML models we need (no conversion!)
3. We only need to port our self-improving profile logic
4. Voice Isolation is native Swift - easy to add

### Migration Effort Comparison

| Approach | UI Work | ML Work | Profile Logic | Total |
|----------|---------|---------|---------------|-------|
| From scratch | High | Low (FluidAudio) | Medium | High |
| Fork Hex | Low | Low (FluidAudio) | Medium | **Low** |
| Port Python | High | High (conversions) | Low | High |

### Next Steps

1. **Clone Hex repo** and explore codebase
2. **Test FluidAudio** speaker embeddings with family voices
3. **Prototype** self-improving profiles in Swift
4. **Integrate** Voice Isolation capture
5. **Rename** and customize UI

---

## FluidAudio Integration Example

```swift
import FluidAudio

// VAD (same as our Python Silero)
let vadManager = try await VadManager()
let segments = try await vadManager.detectSpeech(in: audioURL)

// Speaker Embeddings (replaces our x-vector)
let diarizationManager = try await DiarizationManager()
let embedding = try await diarizationManager.extractEmbedding(from: segment)

// Our custom matching (port from Python)
let profile = voiceLibrary.match(embedding)
if profile.confidence == .high {
    voiceLibrary.autoLearn(profile.name, embedding)
}

// Transcription (replaces SenseVoice)
let asrManager = try await AsrManager()
let transcript = try await asrManager.transcribe(segment)
```

This gives us 90% of the pipeline with minimal code!
