# Always-On Voice Transcription System

An intelligent voice transcription system designed for Apple Silicon, capable of handling multiple speakers in noisy environments with speaker identification.

## Quick Start

### Prerequisites

```bash
pip install coremltools torch soundfile numpy scipy
```

### Getting the Models

Models are not included in git (too large). Generate them:

```bash
# 1. Clone SepReformer and download weights
cd /tmp
git clone https://github.com/dmlguq456/SepReformer.git
cd SepReformer
git lfs pull  # Requires git-lfs: brew install git-lfs

# 2. Run conversion (creates 80MB CoreML model)
cp /path/to/claude-code/voice/separation/convert_to_coreml.py .
python convert_to_coreml.py

# 3. Copy model to voice folder
cp -r SepReformer_Base.mlpackage /path/to/claude-code/voice/separation/models/
```

## System Architecture

The system processes audio through a multi-stage pipeline, optimized for real-time performance on Apple Silicon using CoreML.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          AUDIO INPUT (Continuous)                           │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  1. ENERGY CHECK                                                            │
│     - Fast gate to skip silent sections                                     │
│     - ~1ms latency, near-zero CPU when silent                               │
│     - Threshold: RMS energy > configurable level                            │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  2. SPEECH SEPARATION (SepReformer)                                         │
│     - Separates mixed audio into individual speaker streams                 │
│     - 2-speaker separation (extensible to N speakers)                       │
│     - Runs BEFORE VAD to handle overlapping speech                          │
│     - CoreML model: 80MB, 3.6x real-time on Apple Silicon                   │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                          ┌───────────┴───────────┐
                          ▼                       ▼
┌────────────────────────────────┐  ┌────────────────────────────────┐
│  3a. VAD (Speaker 1 Stream)    │  │  3b. VAD (Speaker 2 Stream)    │
│      - Per-speaker activity    │  │      - Per-speaker activity    │
│      - Segment boundaries      │  │      - Segment boundaries      │
└────────────────────────────────┘  └────────────────────────────────┘
                          │                       │
                          ▼                       ▼
┌────────────────────────────────┐  ┌────────────────────────────────┐
│  4a. SPEAKER ID (Stream 1)     │  │  4b. SPEAKER ID (Stream 2)     │
│      - Match to known voices   │  │      - Match to known voices   │
│      - Learn new speakers      │  │      - Learn new speakers      │
└────────────────────────────────┘  └────────────────────────────────┘
                          │                       │
                          ▼                       ▼
┌────────────────────────────────┐  ┌────────────────────────────────┐
│  5a. TRANSCRIPTION (Stream 1)  │  │  5b. TRANSCRIPTION (Stream 2)  │
│      - SenseVoice CoreML       │  │      - SenseVoice CoreML       │
│      - Per-speaker transcript  │  │      - Per-speaker transcript  │
└────────────────────────────────┘  └────────────────────────────────┘
                          │                       │
                          └───────────┬───────────┘
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  6. OUTPUT                                                                  │
│     - Merged transcript with speaker labels                                 │
│     - Timestamps and confidence scores                                      │
│     - "[Alice] Hello, how are you?" "[Bob] I'm good, thanks!"               │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Design Decisions

### Why Separation Before VAD?

Traditional pipelines run VAD first, then process detected speech. This fails when:
- Two speakers talk simultaneously (overlapping speech)
- One speaker pauses while another continues
- Background speakers create false VAD triggers

By running separation FIRST:
1. Each speaker gets their own clean audio stream
2. VAD runs independently per stream (no interference)
3. Speaker ID can work on clean, single-speaker audio
4. Transcription quality improves dramatically

### Chunking Strategy

Instead of fixed-duration chunks, we use **VAD-based segmentation with a maximum duration cap**:

- **Max duration**: 1-3 minutes (since transcription is fast)
- **Segmentation**: Roll back to last VAD-detected pause when max reached
- **Rationale**: If the user hasn't finished speaking, there's no point transcribing incomplete sentences

### Speaker Identification

Two modes of operation:
1. **Preset voices**: Pre-enrolled voice fingerprints for known speakers
2. **Automatic learning**: System learns new speakers during use

## Components

### Implemented

| Component | Model | Size | Speed | Status |
|-----------|-------|------|-------|--------|
| Speech Separation | SepReformer (CoreML) | 80MB | 3.6x real-time | Done |

### Planned

| Component | Model | Size | Notes |
|-----------|-------|------|-------|
| VAD | Silero VAD / FluidAudio | ~2MB | Per-stream detection |
| Speaker ID | FluidAudio | TBD | Embedding-based matching |
| Transcription | SenseVoice (CoreML) | ~200MB | Already converted |

## Directory Structure

```
voice/
├── README.md                    # This file
├── separation/                  # Speech separation
│   ├── convert_to_coreml.py    # PyTorch → CoreML conversion
│   ├── test_coreml_model.py    # Testing script
│   └── models/
│       └── SepReformer_Base.mlpackage  # 80MB CoreML model
├── vad/                         # Voice Activity Detection (planned)
├── speaker_id/                  # Speaker Identification (planned)
└── transcription/               # Speech-to-Text (planned)
```

## Speech Separation Details

### SepReformer Model

- **Source**: [SepReformer (NeurIPS 2024)](https://github.com/dmlguq456/SepReformer)
- **Architecture**: Dual-path Transformer with EGA (Efficient Global Attention)
- **Training**: WSJ0-2mix dataset
- **Input**: 8kHz mono audio, 4-second chunks
- **Output**: 2 separated speaker streams

### CoreML Conversion

Key challenges solved during conversion:

1. **Dynamic shape access**: EGA modules used `pos_k.shape[0]` which fails in traced models. Fixed by patching with pre-computed fixed values.

2. **Deprecated ops**: Replaced `torch.nn.functional.upsample` with `interpolate`.

3. **Chunked processing**: Model processes 4-second chunks; longer audio is chunked and concatenated.

### Performance Benchmarks

Tested on Apple Silicon (M-series):

| Audio Duration | Processing Time | Real-time Factor |
|----------------|-----------------|------------------|
| 33 seconds     | 10.5s           | 3.1x faster      |
| 60 seconds     | 19.7s           | 3.0x faster      |
| 120 seconds    | 33.5s           | 3.6x faster      |

## Usage

### Testing the Separation Model

```python
import coremltools as ct
import numpy as np
import soundfile as sf

# Load model
model = ct.models.MLModel("separation/models/SepReformer_Base.mlpackage")

# Load audio (must be 8kHz mono)
audio, sr = sf.read("mixture.wav")
assert sr == 8000

# Process in 4-second chunks
chunk_size = 32000  # 4 seconds at 8kHz
output = model.predict({"audio_input": audio[:chunk_size].reshape(1, -1)})

# Get separated speakers
speaker1 = output["speaker1"]
speaker2 = output["speaker2"]
```

### Converting New Models

See `separation/convert_to_coreml.py` for the conversion script. Key steps:

1. Load PyTorch model with weights
2. Patch EGA modules for fixed sizes
3. Wrap in CoreML-compatible wrapper
4. Trace with `torch.jit.trace`
5. Convert with `coremltools.convert()`

## Future Work

1. **Integrate VAD**: Add Silero VAD or FluidAudio for per-stream speech detection
2. **Speaker Embeddings**: Extract and match voice fingerprints
3. **Transcription Pipeline**: Connect SenseVoice for final transcription
4. **End-to-end System**: Unified API for continuous voice processing
5. **N-speaker Support**: Extend beyond 2 speakers with MossFormer2 or similar

## References

- [SepReformer Paper](https://arxiv.org/abs/2409.09627) - NeurIPS 2024
- [SenseVoice](https://github.com/FunAudioLLM/SenseVoice) - Transcription model
- [FluidAudio](https://github.com/amaai-lab/FluidAudio) - VAD + Speaker ID for Apple Silicon
- [Silero VAD](https://github.com/snakers4/silero-vad) - Lightweight VAD
