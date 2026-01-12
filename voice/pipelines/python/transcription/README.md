# SenseVoice CoreML Transcription

Fast, production-ready speech recognition using SenseVoice converted to CoreML for Apple Silicon Neural Engine.

## Performance

| Audio Length | Time | Speed |
|--------------|------|-------|
| 15s | 62ms | 240x real-time |
| 1 min | 156ms | 385x real-time |
| 3 min | 480ms | 375x real-time |
| 5 min | 844ms | 355x real-time |

## Why SenseVoice?

### Market Research

We evaluated several ASR options for on-device transcription:

| Model | Pros | Cons | Decision |
|-------|------|------|----------|
| **Whisper** | Best accuracy, multi-language | Slow (3-5s for 15s audio), large model | Too slow for real-time |
| **Breeze-ASR-25** | CoreML ready, fast | Traditional Chinese only, 7.9s for 14s audio | Wrong language output |
| **Parakeet (Hex app)** | Very fast CoreML, used in production | Proprietary, English-focused | Not available |
| **SenseVoice** | Fast, multi-language (zh/en/ja/ko/yue), small model | No CoreML version | **Selected - we convert it** |

### Why We Chose SenseVoice

1. **Multi-language**: Supports Chinese, English, Japanese, Korean, Cantonese
2. **Fast inference**: ~30ms per 15s chunk on Neural Engine
3. **Good accuracy**: Comparable to Whisper for supported languages
4. **Small model**: ~450MB CoreML model
5. **Open source**: Can be converted and optimized

## Architecture

### CoreML Conversion

```
PyTorch Model (HuggingFace)
    ↓ torch.jit.trace
TorchScript
    ↓ coremltools.convert
CoreML (.mlpackage)
    ↓ Neural Engine
~30ms inference
```

### Key Design Decisions

#### 1. Fixed Frame Size (not EnumeratedShapes)

**Problem**: CoreML's `EnumeratedShapes` allows variable input sizes, but causes CPU fallback (~900ms instead of ~30ms).

**Solution**: Use fixed frame size. ANE requires compile-time known shapes for optimization.

```python
# Bad: EnumeratedShapes → CPU fallback (900ms)
ct.EnumeratedShapes(shapes=[(1, 50, 560), (1, 100, 560), ...])

# Good: Fixed shape → ANE (30ms)
ct.TensorType(shape=(1, 250, 560), ...)
```

#### 2. 250 Frames as Default

We benchmarked all frame counts (150, 250, 500, 750, 1000, 1500, 2000):

| Frames | Max Duration | Single Inference | Best For |
|--------|--------------|------------------|----------|
| 150 | 9s | 22ms | - |
| **250** | **15s** | **30ms** | **Most use cases** |
| 500 | 30s | 68ms | 5+ min audio |
| 1000 | 60s | 175ms | - |
| 2000 | 120s | 580ms | - |

**Finding**: 250 frames is optimal for audio up to 3 minutes. Larger frames have O(n²) attention overhead that outweighs fewer chunks.

#### 3. Chunking for Long Audio

For audio longer than 15s, we chunk with 1s overlap:

```
[====chunk1====]
           [====chunk2====]
                      [====chunk3====]
         ↑ 1s overlap to avoid cutting words
```

#### 4. torchaudio for Mel Spectrogram

**Problem**: librosa.melspectrogram is slow (~1000ms for 14s audio).

**Solution**: torchaudio is 800x faster (~1.2ms).

```python
# Slow: librosa (1000ms)
librosa.feature.melspectrogram(y=audio, ...)

# Fast: torchaudio (1.2ms)
mel_transform = torchaudio.transforms.MelSpectrogram(...)
mel_transform(audio_tensor)
```

#### 5. soundfile for Audio Loading

**Problem**: librosa.load is slow for pcm_s32le format (~1300ms).

**Solution**: soundfile is 1000x faster (~1ms).

```python
# Slow: librosa (1300ms for pcm_s32le)
audio, sr = librosa.load(path, sr=16000)

# Fast: soundfile (1ms)
audio, sr = sf.read(path)
```

## Usage

### Basic Transcription

```python
from sensevoice_coreml import SenseVoiceCoreML

model = SenseVoiceCoreML()
text, elapsed = model.transcribe("audio.wav")
print(f"{text} ({elapsed*1000:.0f}ms)")
```

### Voice Input (Hold-to-Record)

```bash
python run.py
# Hold Option key to record
# Release to transcribe
# Press Escape to quit
```

## File Structure

```
transcription/
├── README.md              # This file
├── sensevoice_coreml.py   # Production transcription class
├── run.py                 # Hold-to-record voice input
├── build_models.py        # Rebuild CoreML models
├── requirements.txt       # Python dependencies
├── .gitignore             # Ignore large files
├── models/                # CoreML models (gitignored, ~450MB each)
│   ├── sensevoice-250.mlpackage   # Default (recommended)
│   ├── sensevoice-500.mlpackage   # For 5+ min audio
│   └── ... other variants
├── pytorch/               # Source PyTorch model (gitignored, ~900MB)
└── test/                  # Test audio files
    ├── chinese-14s.wav
    └── english-31s.wav
```

## Setup

### 1. Install Dependencies

```bash
pip install -r requirements.txt
```

### 2. Download PyTorch Model

```bash
# From HuggingFace
git lfs install
git clone https://huggingface.co/FunAudioLLM/SenseVoiceSmall pytorch/
```

### 3. Build CoreML Models

```bash
python build_models.py
# Builds all frame variants (150, 250, 500, 750, 1000, 1500, 2000)
# Takes ~5-7 minutes
```

### 4. Test

```bash
python sensevoice_coreml.py
# Runs test transcription on sample audio
```

## Benchmark Results

### Frame Count vs Audio Length

| Audio | 150 | 250 | 500 | 750 | 1000 | 1500 | 2000 |
|-------|-----|-----|-----|-----|------|------|------|
| 15s | 65ms | **62ms** | 68ms | 114ms | 174ms | 381ms | 579ms |
| 30s | 108ms | **95ms** | 136ms | 115ms | 173ms | 377ms | 575ms |
| 1min | 194ms | **156ms** | 203ms | 230ms | 350ms | 377ms | 622ms |
| 3min | 641ms | **480ms** | 485ms | 623ms | 764ms | 1229ms | 1525ms |
| 5min | 1040ms | 958ms | **844ms** | 979ms | 1209ms | 1854ms | 2005ms |

**Conclusion**: 250 frames wins for most cases. Only use 500 frames for 5+ minute recordings.

## Comparison with Other Backends

| Backend | 14s Chinese | 31s English | Notes |
|---------|-------------|-------------|-------|
| **CoreML (this)** | **47ms** | **149ms** | Neural Engine, chunked |
| Metal (sensevoice.cpp) | 782ms | 1355ms | GPU, includes model load |
| Whisper.cpp | ~3000ms | ~6000ms | CPU/GPU |

CoreML is **16-25x faster** than Metal for this model.
