# Voice Pipeline Research Status

## Current System Architecture

```
Audio Input
    ↓
[Separation] ← SepReformer CoreML (8kHz, 4s chunks)
    ↓
[VAD] ← Silero (16kHz)
    ↓
[Speaker ID] ← x-vector (16kHz, 14ms/5s)
    ↓
[Transcription] ← SenseVoice CoreML (16kHz)
    ↓
Output: [Speaker] Text
```

## Problems & Solutions Status

| Problem | Status | Solution |
|---------|--------|----------|
| Slow embedding (ECAPA 95ms) | ✅ Solved | x-vector (14ms) |
| Score readability | ✅ Solved | Min-max transform |
| Quick turn-taking (edited content) | ❌ Not solved | Sliding window doesn't work with x-vector |
| Overlapping speech (family) | ⚠️ Needs work | SepReformer exists but needs testing |

## The Overlapping Speech Problem

### Real-World Scenario
```
Person A: "你今天去哪里——"
Person B:          "——我去了超市"
             ↑ OVERLAP ↑
```

### Why This Is Hard
1. **Two voices at same time** → Can't use VAD to split
2. **Mixed frequencies** → Can't use simple filtering
3. **Real-time requirement** → Can't use slow offline models

## State of the Art Research (2025)

### Models Comparison

| Model | SI-SNRi | Params | Real-time? | Notes |
|-------|---------|--------|------------|-------|
| [SepFormer](https://huggingface.co/speechbrain/sepformer-wsj02mix) | 22.3 dB | 26M | No (heavy) | Best quality |
| [Conv-TasNet](https://arxiv.org/abs/2205.13657) | 15.3 dB | 5.1M | Yes | Original real-time model |
| [SPMamba](https://arxiv.org/html/2404.02063v1) | 22.1 dB | 7M | Yes | State Space Model, efficient |
| [Tiny-Sepformer](https://www.researchgate.net/publication/363646575_Tiny-Sepformer_A_Tiny_Time-Domain_Transformer_Network_For_Speech_Separation) | 20.8 dB | 8M | Yes | Compressed SepFormer |
| [Microsoft Real-time](https://www.microsoft.com/en-us/research/publication/towards-real-time-single-channel-speech-separation-in-noisy-and-reverberant-environments/) | ~20 dB | Small | Yes | 20ms latency, 10x less complex |
| SepReformer (ours) | ? | ? | ~10x RT | Already converted to CoreML |

### Commercial Solutions

- **[pyannoteAI](https://www.pyannote.ai/)**: Premium diarization with overlap handling, 20% better than open-source
- **[AssemblyAI](https://www.assemblyai.com/blog/top-speaker-diarization-libraries-and-apis)**: 30% improvement in noisy environments, 43% for short utterances

### MISP 2025 Challenge Winners

- Achieved 8.88% DER with hybrid approach
- Uses WavLM model for overlap-adaptive diarization
- Source: [Overlap-Adaptive Hybrid Speaker Diarization](https://arxiv.org/html/2505.22013v1)

## Current Assets

### We Already Have
1. **SepReformer CoreML** at `voice/separation/models/SepReformer_Base.mlpackage`
   - Input: 8kHz, 4-second chunks
   - Output: 2 separated speaker streams
   - Speed: ~10x real-time (untested on overlapping speech)

2. **x-vector** for speaker ID (fast)

3. **SenseVoice CoreML** for transcription

### What We Need to Test
1. Does SepReformer work on **real overlapping family speech**?
2. What's the quality (SI-SNR) on natural conversation?
3. Can we chain: Separation → VAD → Speaker ID → Transcription?

## Proposed Experiments

### Experiment 1: Test SepReformer on Real Overlapping Speech
- Record 30s of two people talking over each other
- Process through SepReformer
- Measure: (a) quality of separation, (b) processing time

### Experiment 2: End-to-End Pipeline with Separation
- Input: Mixed family conversation
- Pipeline: Separation → VAD → Speaker ID → Transcription
- Measure: Speaker identification accuracy, transcription quality

### Experiment 3: Compare Separation Models
- If SepReformer doesn't work well, try:
  - Conv-TasNet (smaller, faster)
  - Tiny-Sepformer (if available)
  - SPMamba (state-of-the-art efficient)

## Key Questions to Answer

1. **Does separation help or hurt?**
   - Separation might introduce artifacts that hurt transcription
   - Need A/B test: with vs without separation

2. **When to use separation?**
   - All the time? Only when overlap detected?
   - Detection: Can we detect overlap before separating?

3. **Speaker consistency across chunks?**
   - SepReformer processes 4s chunks
   - "Speaker 1" in chunk 1 might be "Speaker 2" in chunk 2
   - Need: Speaker tracking across chunks

## Separation Model Benchmark Results (2025-01-10)

Tested on 27.7s audio from `test_recording.wav`:

| Model | Load Time | Sep Time | RTF | Speed | Notes |
|-------|-----------|----------|-----|-------|-------|
| SepReformer-CoreML | 50.7s | 15.70s | 0.567 | 1.8x RT | Our converted model |
| SepFormer-WSJ02mix | 18.8s | 10.71s | 0.387 | 2.6x RT | State-of-the-art |
| SepFormer-WHAM | 16.2s | 10.40s | 0.375 | 2.7x RT | Noisy variant |

### Key Finding: Test Audio Problem
The test audio is **NOT overlapping speech** - it's a YouTube video playback with English and Chinese mixed. Original transcription:
```
"The iPhone 17 pro is the best iPhone 4 creators..."
```

### Separation Quality
- **SepReformer-CoreML**: Best transcription preservation (kept both EN/ZH)
- **SepFormer-WSJ02mix**: Garbled fragments
- **SepFormer-WHAM**: Very poor (designed for noisy environments, not mixed content)

### Why Models Performed Poorly
1. Models trained on **clean 2-speaker mixtures** (WSJ, LibriMix)
2. Test audio is **video content**, not overlapping conversation
3. **Mixed languages** (English + Chinese) confuse models
4. **No actual speaker overlap** in the recording

## Next Steps

1. **Immediate**: Record **REAL overlapping speech** with 莲老太 and 傻狗
   - Two people talking over each other
   - Natural family conversation
2. **Re-test**: Run all models on actual overlapping speech
3. **Evaluate**: Measure separation quality on real data
4. **Decide**: Keep SepReformer or switch to SepFormer

## References

- [Speech Separation Papers](https://paperswithcode.com/task/speech-separation)
- [PyAnnote Speaker Diarization](https://github.com/pyannote/pyannote-audio)
- [SpeechBrain Separation](https://speechbrain.github.io/)
- [Advances in Speech Separation (2025)](https://arxiv.org/html/2508.10830v1)
