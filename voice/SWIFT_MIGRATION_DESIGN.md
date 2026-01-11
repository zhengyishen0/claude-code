# Swift Voice System Migration Design

## Part 1: Current Python Architecture Analysis

### 1.1 System Overview

The current Python voice system has two modes:

```
┌─────────────────────────────────────────────────────────────────┐
│                     OFFLINE PIPELINE (pipeline.py)              │
│  Audio File → Separation → VAD → Speaker ID → Transcription     │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                      LIVE PIPELINE (live.py)                    │
│  Microphone → VAD (streaming) → Speaker ID → Transcription      │
│                    ↓                                            │
│              Self-Improving Speaker Profiles                    │
└─────────────────────────────────────────────────────────────────┘
```

### 1.2 Pipeline Stages (Detailed)

#### Stage 1: Audio Input
- **Sample Rate**: 16kHz (standard), 8kHz (for separation)
- **Format**: Mono, float32
- **Sources**: File (WAV/MP3) or live microphone via `sounddevice`

#### Stage 2: Speech Separation (Optional)
- **Model**: SepReformer (CoreML)
- **Location**: `voice/separation/models/SepReformer_Base.mlpackage`
- **Input**: 8kHz mono, 4-second chunks (32,000 samples)
- **Output**: 2 separated speaker streams
- **Speed**: ~1.8x real-time
- **Purpose**: Separate overlapping speakers

```python
# Processing flow
audio_8k = resample(audio, orig_sr, 8000)
for chunk in chunks(audio_8k, 32000):
    output = separator.predict({"audio_input": chunk})
    speaker1.append(output["speaker1"])
    speaker2.append(output["speaker2"])
```

#### Stage 3: Voice Activity Detection (VAD)
- **Model**: Silero VAD (PyTorch)
- **Size**: ~2MB
- **Input**: 16kHz, 512-sample windows (~32ms)
- **Output**: Speech probability (0-1) per window
- **Thresholds**:
  - `speech_threshold`: 0.5
  - `min_speech_duration`: 300ms
  - `min_silence_duration`: 300ms

```python
# Streaming VAD in live.py
for audio_chunk in stream:
    prob = vad_model(chunk, SAMPLE_RATE)
    if prob >= threshold:
        if not is_speech:
            speech_start = current_time
            is_speech = True
        speech_buffer.extend(chunk)
    else:
        if is_speech and silence > min_silence:
            yield speech_buffer  # Segment complete
            is_speech = False
```

#### Stage 4: Speaker Identification
- **Model**: x-vector (SpeechBrain)
- **Source**: `speechbrain/spkrec-xvect-voxceleb`
- **Embedding**: 512-dimensional
- **Speed**: ~14ms for 5s audio
- **Matching**: Cosine similarity with threshold 0.25

```python
# Embedding extraction
audio_tensor = torch.from_numpy(audio).unsqueeze(0)
embedding = model.encode_batch(audio_tensor)  # [1, 512]
embedding = embedding / np.linalg.norm(embedding)  # Normalize

# Matching
similarity = np.dot(query_emb, profile_emb)  # Cosine similarity
if similarity >= threshold:
    return speaker_name, similarity
```

#### Stage 5: Transcription
- **Model**: SenseVoice (CoreML)
- **Location**: `voice/transcription/models/sensevoice-500-itn.mlmodelc`
- **Size**: 448MB
- **Input**: 16kHz mono, up to ~30s per chunk
- **Languages**: Chinese, English, Japanese, Korean, Cantonese
- **Features**:
  - LFR (Low Frame Rate): Stack 7 frames, skip 6 → 60ms per frame
  - CTC decoding with greedy search
  - Optional ITN (punctuation)

```python
# Feature extraction
mel = mel_spectrogram(audio)  # [time, 80]
lfr = stack_frames(mel, m=7, n=6)  # [time/6, 560]
lfr = pad_to_fixed_frames(lfr, 500)  # [500, 560]

# Inference
logits = model.predict({"audio_features": lfr})
text = ctc_greedy_decode(logits)
```

### 1.3 Self-Improving Speaker Profiles (live.py)

This is the **key innovation** - speaker profiles automatically improve over time.

#### Two-Layer Profile Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    SpeakerProfile                           │
├─────────────────────────────────────────────────────────────┤
│  CORE LAYER (max 5 embeddings)                              │
│  - Frequent voice patterns (within 1σ of centroid)         │
│  - Used for primary matching                                │
│  - Updated when high-confidence match                       │
├─────────────────────────────────────────────────────────────┤
│  BOUNDARY LAYER (max 10 embeddings)                         │
│  - Edge-case voice patterns (1σ to 2σ from centroid)       │
│  - Used for initial screening                               │
│  - Captures voice variations (tired, sick, emotional)       │
├─────────────────────────────────────────────────────────────┤
│  METADATA                                                   │
│  - centroid: Mean of core embeddings                        │
│  - std_dev: Standard deviation of distances                 │
│  - all_distances: History for σ calculation                 │
└─────────────────────────────────────────────────────────────┘
```

#### Two-Phase Matching Algorithm

```python
def match(embedding):
    # Phase 1: Boundary check (fast screening)
    boundary_matches = []
    for speaker in speakers:
        score = speaker.max_similarity_to_boundary(embedding)
        if score >= BOUNDARY_THRESHOLD (0.35):
            boundary_matches.append((speaker, score))

    if len(boundary_matches) == 0:
        return None  # Unknown speaker

    if len(boundary_matches) == 1:
        return boundary_matches[0]  # Clear match

    # Phase 2: Core refinement (resolve conflicts)
    core_scores = []
    for speaker, _ in boundary_matches:
        core_score = speaker.max_similarity_to_core(embedding)
        core_scores.append((speaker, core_score))

    best, second = sorted(core_scores, reverse=True)[:2]
    if best.score - second.score >= CONFLICT_MARGIN (0.1):
        return best  # Core distinguishes
    else:
        return f"[{best.name}/{second.name}?]"  # Conflict
```

#### Auto-Learning

```python
def auto_learn(speaker_name, embedding, match_score):
    """Automatically improve profile from high-confidence matches."""
    if match_score >= AUTO_LEARN_THRESHOLD (0.55):
        profile = speakers[speaker_name]

        # Classify embedding by distance from centroid
        dist = cosine_distance(embedding, profile.centroid)

        if dist < 1.0 * profile.std_dev:
            # Within 1σ → Add to core (if diverse enough)
            if len(profile.core) < MAX_CORE:
                if is_diverse(embedding, profile.core, min_dist=0.1):
                    profile.core.append(embedding)
                    profile.update_centroid()

        elif dist < 2.0 * profile.std_dev:
            # Between 1σ and 2σ → Add to boundary
            if len(profile.boundary) < MAX_BOUNDARY:
                if is_diverse(embedding, profile.boundary, min_dist=0.1):
                    profile.boundary.append(embedding)
```

#### Diversity-Based Selection (for enrollment)

```python
def select_diverse_embeddings(embeddings, max_count=5):
    """Farthest-first traversal for maximum diversity."""
    selected = [embeddings[0]]
    remaining = embeddings[1:]

    while len(selected) < max_count and remaining:
        # Find embedding farthest from all selected
        best = max(remaining,
                   key=lambda e: min(cosine_distance(e, s) for s in selected))
        selected.append(best)
        remaining.remove(best)

    return selected
```

### 1.4 Performance Benchmarks (Current Python)

| Stage | Model | Time (5s audio) | Speed |
|-------|-------|-----------------|-------|
| Separation | SepReformer CoreML | ~2.8s | 1.8x RT |
| VAD | Silero PyTorch | ~5ms | 1000x RT |
| Speaker ID | x-vector | ~14ms | 350x RT |
| Transcription | SenseVoice CoreML | ~200ms | 25x RT |
| **Total** | | ~3.0s | **1.7x RT** |

*Note: Separation is the bottleneck. Without separation: ~220ms total (~23x RT)*

---

## Part 2: Swift App Design Proposal

### 2.1 Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     macOS Menu Bar App                          │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐           │
│  │ Record   │ │ Settings │ │ Speakers │ │ History  │           │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘           │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Audio Capture Layer                          │
│  ┌─────────────────────┐    ┌─────────────────────┐            │
│  │  Standard Capture   │    │  Voice Isolation    │            │
│  │  (AVAudioEngine)    │    │  (Voice Processing) │            │
│  └─────────────────────┘    └─────────────────────┘            │
│              │                        │                         │
│              └────────┬───────────────┘                         │
│                       ▼                                         │
│              ┌─────────────────┐                                │
│              │  Audio Buffer   │                                │
│              │  (Ring Buffer)  │                                │
│              └─────────────────┘                                │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Processing Pipeline                          │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  VAD (Streaming)                                         │   │
│  │  - Silero VAD (CoreML) or Energy-based                   │   │
│  │  - Emits speech segments as they complete                │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│                              ▼                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Parallel Processing (per segment)                       │   │
│  │  ┌─────────────────┐  ┌─────────────────┐               │   │
│  │  │  Speaker ID     │  │  Transcription  │               │   │
│  │  │  (x-vector)     │  │  (SenseVoice)   │               │   │
│  │  │  CoreML         │  │  CoreML         │               │   │
│  │  └─────────────────┘  └─────────────────┘               │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│                              ▼                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Self-Improving Speaker Profiles                         │   │
│  │  - Two-layer (core/boundary) architecture                │   │
│  │  - Auto-learning from high-confidence matches            │   │
│  │  - Persisted to disk (JSON)                              │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Output & Storage                             │
│  - Live transcript display (NSWindow)                           │
│  - Audio recording (WAV)                                        │
│  - Session history (SQLite or JSON)                             │
│  - Metrics logging (for comparison testing)                     │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 Key Swift Components

#### 2.2.1 Audio Capture Manager

```swift
class AudioCaptureManager: ObservableObject {
    private let engine = AVAudioEngine()
    private let inputNode: AVAudioInputNode

    @Published var isRecording = false
    @Published var voiceIsolationEnabled = false

    // Dual-stream for A/B comparison
    private var standardBuffer: RingBuffer<Float>
    private var isolatedBuffer: RingBuffer<Float>

    func startRecording(mode: CaptureMode) async throws {
        let inputNode = engine.inputNode

        // Configure voice processing based on mode
        switch mode {
        case .standard:
            try inputNode.setVoiceProcessingEnabled(false)
        case .voiceIsolation:
            try inputNode.setVoiceProcessingEnabled(true)
        case .parallel:
            // Run two engines for A/B comparison
            try startParallelCapture()
        }

        // Install tap and start
        inputNode.installTap(onBus: 0, bufferSize: 512, format: format) { buffer, time in
            self.processAudioBuffer(buffer, time: time)
        }

        try engine.start()
        isRecording = true
    }
}
```

#### 2.2.2 Streaming VAD

```swift
class StreamingVAD {
    private let model: MLModel  // Silero VAD CoreML
    private var audioBuffer: [Float] = []
    private var isInSpeech = false
    private var speechStart: TimeInterval = 0
    private var silenceFrames = 0

    let speechThreshold: Float = 0.5
    let minSpeechDuration: TimeInterval = 0.3
    let minSilenceDuration: TimeInterval = 0.3

    func processChunk(_ chunk: [Float], timestamp: TimeInterval) -> SpeechSegment? {
        audioBuffer.append(contentsOf: chunk)

        // Get speech probability
        let prob = predictSpeechProbability(chunk)

        if prob >= speechThreshold {
            silenceFrames = 0
            if !isInSpeech {
                isInSpeech = true
                speechStart = timestamp
                speechBuffer = []
            }
            speechBuffer.append(contentsOf: chunk)
        } else {
            if isInSpeech {
                silenceFrames += 1
                speechBuffer.append(contentsOf: chunk)

                if silenceFrames >= minSilenceFrames {
                    // Speech ended
                    isInSpeech = false
                    let duration = timestamp - speechStart

                    if duration >= minSpeechDuration {
                        let segment = SpeechSegment(
                            audio: speechBuffer,
                            start: speechStart,
                            end: timestamp
                        )
                        speechBuffer = []
                        return segment
                    }
                }
            }
        }
        return nil
    }
}
```

#### 2.2.3 Self-Improving Speaker Profile (Swift)

```swift
class SpeakerProfile: Codable {
    let name: String
    var core: [[Float]]          // Max 5 embeddings
    var boundary: [[Float]]      // Max 10 embeddings
    var centroid: [Float]?
    var stdDev: Float = 0.2
    var allDistances: [Float] = []

    static let maxCore = 5
    static let maxBoundary = 10
    static let minDiversity: Float = 0.1

    func addEmbedding(_ embedding: [Float]) -> AddResult {
        guard let centroid = centroid else {
            core.append(embedding)
            self.centroid = embedding
            return .core
        }

        let dist = cosineDistance(embedding, centroid)
        allDistances.append(dist)
        updateStdDev()

        if dist < 1.0 * stdDev {
            // Core candidate
            if core.count < Self.maxCore && isDiverse(embedding, from: core) {
                core.append(embedding)
                updateCentroid()
                return .core
            }
        } else if dist < 2.0 * stdDev {
            // Boundary candidate
            if boundary.count < Self.maxBoundary && isDiverse(embedding, from: boundary) {
                boundary.append(embedding)
                return .boundary
            }
        }
        return .rejected
    }

    func maxSimilarityToCore(_ embedding: [Float]) -> Float {
        core.map { cosineSimilarity(embedding, $0) }.max() ?? 0
    }

    func maxSimilarityToBoundary(_ embedding: [Float]) -> Float {
        (core + boundary).map { cosineSimilarity(embedding, $0) }.max() ?? 0
    }
}
```

#### 2.2.4 Voice Library with Two-Phase Matching

```swift
class VoiceLibrary: ObservableObject {
    @Published var speakers: [String: SpeakerProfile] = [:]

    let boundaryThreshold: Float = 0.35
    let coreThreshold: Float = 0.45
    let autoLearnThreshold: Float = 0.55
    let conflictMargin: Float = 0.1

    func match(_ embedding: [Float]) -> MatchResult {
        // Phase 1: Boundary screening
        var boundaryMatches: [(String, Float, SpeakerProfile)] = []
        for (name, profile) in speakers {
            let score = profile.maxSimilarityToBoundary(embedding)
            if score >= boundaryThreshold {
                boundaryMatches.append((name, score, profile))
            }
        }

        guard !boundaryMatches.isEmpty else {
            return .unknown
        }

        if boundaryMatches.count == 1 {
            let (name, score, _) = boundaryMatches[0]
            let confidence: Confidence = score >= autoLearnThreshold ? .high : .medium
            return .matched(name: name, score: score, confidence: confidence)
        }

        // Phase 2: Core refinement
        let coreScores = boundaryMatches.map { (name, _, profile) in
            (name, profile.maxSimilarityToCore(embedding))
        }.sorted { $0.1 > $1.1 }

        let (bestName, bestScore) = coreScores[0]
        let (secondName, secondScore) = coreScores[1]

        if bestScore - secondScore >= conflictMargin {
            let confidence: Confidence = bestScore >= autoLearnThreshold ? .high : .medium
            return .matched(name: bestName, score: bestScore, confidence: confidence)
        } else {
            return .conflict(candidates: [bestName, secondName], score: bestScore)
        }
    }

    func autoLearn(name: String, embedding: [Float], score: Float) -> Bool {
        guard score >= autoLearnThreshold,
              let profile = speakers[name] else { return false }

        let result = profile.addEmbedding(embedding)
        if result != .rejected {
            save()
            return true
        }
        return false
    }
}
```

### 2.3 Parallel Stream Comparison (Experiment Feature)

```swift
class ParallelCaptureManager {
    private let standardEngine = AVAudioEngine()
    private let isolatedEngine = AVAudioEngine()

    private let standardPipeline: VoicePipeline
    private let isolatedPipeline: VoicePipeline

    @Published var metrics = ComparisonMetrics()

    func startParallelCapture() async throws {
        // Configure standard capture
        let stdInput = standardEngine.inputNode
        try stdInput.setVoiceProcessingEnabled(false)

        // Configure isolated capture
        let isoInput = isolatedEngine.inputNode
        try isoInput.setVoiceProcessingEnabled(true)

        // Install taps
        stdInput.installTap(onBus: 0, bufferSize: 512, format: format) { buffer, time in
            Task {
                let result = await self.standardPipeline.process(buffer)
                self.recordMetrics(result, stream: .standard)
            }
        }

        isoInput.installTap(onBus: 0, bufferSize: 512, format: format) { buffer, time in
            Task {
                let result = await self.isolatedPipeline.process(buffer)
                self.recordMetrics(result, stream: .isolated)
            }
        }

        try standardEngine.start()
        try isolatedEngine.start()
    }
}

struct ComparisonMetrics {
    // Audio Quality
    var standardNoiseFloor: Float = 0
    var isolatedNoiseFloor: Float = 0
    var standardSNR: Float = 0
    var isolatedSNR: Float = 0

    // Speed (per stage)
    var standardVADTime: TimeInterval = 0
    var isolatedVADTime: TimeInterval = 0
    var standardSpeakerIDTime: TimeInterval = 0
    var isolatedSpeakerIDTime: TimeInterval = 0
    var standardTranscriptionTime: TimeInterval = 0
    var isolatedTranscriptionTime: TimeInterval = 0

    // Accuracy
    var standardSegmentCount: Int = 0
    var isolatedSegmentCount: Int = 0
    var standardWordCount: Int = 0
    var isolatedWordCount: Int = 0
    var speakerIDMatches: Int = 0
    var speakerIDConflicts: Int = 0
}
```

### 2.4 Menu Bar UI Design

```
┌──────────────────────────────────────┐
│  🎤 Voice                        ▼  │
├──────────────────────────────────────┤
│  ● Recording... (00:23)              │
│  ──────────────────────────────────  │
│  [莲老太] 你今天去哪里了？           │
│  [傻狗] 我去了超市买菜。             │
│  [莲老太?] 买了什么菜？              │
│  ──────────────────────────────────  │
│                                      │
│  ⚙️ Settings                         │
│    ☑️ Voice Isolation                │
│    ☐ Parallel Comparison Mode        │
│    ☐ Show Metrics                    │
│                                      │
│  👥 Speakers (3)                     │
│    莲老太: 5 core, 8 boundary        │
│    傻狗: 4 core, 6 boundary          │
│    + Add Speaker                     │
│                                      │
│  📊 Session Stats                    │
│    Duration: 2:23                    │
│    Segments: 12                      │
│    Known: 10 | Unknown: 2            │
│                                      │
│  ⏹️ Stop Recording                   │
└──────────────────────────────────────┘
```

### 2.5 Migration Strategy

#### Phase 1: Core Pipeline (Week 1-2)
1. Port CoreML model loading (SenseVoice, x-vector)
2. Implement streaming VAD in Swift
3. Basic audio capture with/without Voice Isolation
4. Simple transcript output

#### Phase 2: Self-Improving Profiles (Week 2-3)
1. Port two-layer SpeakerProfile class
2. Implement two-phase matching algorithm
3. Auto-learning from high-confidence matches
4. JSON persistence for profiles

#### Phase 3: Menu Bar App (Week 3-4)
1. SwiftUI menu bar interface
2. Live transcript display
3. Speaker management UI
4. Settings panel

#### Phase 4: Comparison Testing (Week 4-5)
1. Parallel stream capture
2. Metrics collection framework
3. A/B comparison reports
4. Performance optimization

### 2.6 Model Conversion Requirements

| Model | Current Format | Swift Target | Notes |
|-------|---------------|--------------|-------|
| SenseVoice | CoreML (.mlmodelc) | CoreML | Ready to use |
| SepReformer | CoreML (.mlpackage) | CoreML | Ready to use |
| x-vector | PyTorch (SpeechBrain) | CoreML | **Needs conversion** |
| Silero VAD | PyTorch | CoreML | **Needs conversion** |

#### x-vector Conversion Plan
```python
# Convert x-vector to CoreML
import coremltools as ct
from speechbrain.inference.speaker import EncoderClassifier

model = EncoderClassifier.from_hparams(source="speechbrain/spkrec-xvect-voxceleb")
# Trace and convert...
```

#### Silero VAD Conversion Plan
```python
# Convert Silero VAD to CoreML
model, utils = torch.hub.load('snakers4/silero-vad', 'silero_vad')
# Trace with fixed input shape and convert...
```

---

## Summary

The Swift migration preserves all key features from Python:

| Feature | Python Implementation | Swift Implementation |
|---------|----------------------|---------------------|
| Streaming VAD | `VADProcessor` class | `StreamingVAD` class |
| Two-layer profiles | `SpeakerProfile` with core/boundary | Same architecture in Swift |
| Two-phase matching | `VoiceLibrary.match()` | Same algorithm in Swift |
| Auto-learning | `auto_learn()` with σ-based classification | Same logic in Swift |
| Diversity selection | `_select_diverse_embeddings()` | Same algorithm in Swift |
| Parallel processing | `ThreadPoolExecutor` | Swift `async/await` + `TaskGroup` |

The main addition is **Voice Isolation comparison** - running two parallel streams to measure the impact of Apple's voice processing on transcription and speaker ID accuracy.
