# Voice Pipeline Test Checklist

Use this checklist after any major refactoring to verify all components work correctly.

---

## 1. Setup & Dependencies

### 1.1 Setup Script
```bash
cd voice
./scripts/setup.sh
```

- [ ] Silero VAD downloads to `models/onnx/silero_vad.onnx`
- [ ] ONNX Runtime downloads to `pipelines/kmp/libs/onnxruntime-osx-arm64-*/`
- [ ] ONNX wrapper builds (if present)
- [ ] CoreML models detected in `models/coreml/`
- [ ] ONNX models detected in `models/onnx/`

### 1.2 Directory Structure
- [ ] `models/coreml/` contains compiled models (.mlmodelc)
- [ ] `models/onnx/` contains ONNX models (.onnx)
- [ ] `models/assets/` contains vocab/tokenizer files (.bpe.model, .txt, .bin)
- [ ] `data/` exists for voice library storage
- [ ] `pipelines/` contains kmp, python, swift subdirectories

---

## 2. Model Conversion Scripts

### 2.1 Unified CLI
```bash
cd voice
python scripts/convert.py --help
```
- [ ] Help message displays without errors
- [ ] Shows available model types: asr, speaker, separation, vad, all
- [ ] Shows format options: coreml, onnx

### 2.2 Individual Converters
Test each converter can be invoked (may require dependencies):

```bash
# Check converters exist and are executable
ls -la scripts/converters/
```

- [ ] `asr.py` exists
- [ ] `speaker_id.py` exists
- [ ] `separation.py` exists
- [ ] `export_onnx.py` exists

---

## 3. Python Pipeline

### 3.1 Import Test
```bash
cd voice/pipelines/python
python3 -c "from transcription.sensevoice_coreml import *; print('Transcription OK')"
python3 -c "from speaker_id.speaker_embeddings import *; print('Speaker ID OK')"
python3 -c "from vad.silero_vad import *; print('VAD OK')"
python3 -c "import live; print('Live pipeline OK')"
```

- [ ] Transcription module imports (sensevoice_coreml)
- [ ] Speaker ID module imports (speaker_embeddings)
- [ ] VAD module imports (silero_vad)
- [ ] Main live.py imports

### 3.2 Live Pipeline Test
```bash
cd voice/pipelines/python
python3 live.py
```

- [ ] Audio capture starts
- [ ] VAD detects speech
- [ ] Transcription outputs text
- [ ] Speaker identification works

---

## 4. Swift Pipeline

### 4.1 Build Test
```bash
cd voice/pipelines/swift
swift build
```

- [ ] Compiles without errors
- [ ] Links against CoreML framework
- [ ] Finds SentencePiece dependency

### 4.2 Model Path Test
```bash
cd voice/pipelines/swift
swift run VoicePipelineTest --check-models
# Or inspect Sources for model paths
```

- [ ] Paths reference `models/coreml/` or `models/assets/`
- [ ] No references to old YouPu or scattered locations

### 4.3 Live Test
```bash
cd voice/pipelines/swift
swift run VoicePipelineTest
```

- [ ] Audio capture starts
- [ ] VAD processes correctly
- [ ] ASR transcribes speech
- [ ] Speaker ID matches speakers
- [ ] Output format: `[Speaker] (start-end) text [Xms]`

---

## 5. KMP Pipeline (macOS)

### 5.1 Build Test
```bash
cd voice/pipelines/kmp
./gradlew build
```

- [ ] Gradle syncs successfully
- [ ] cinterop definitions found (CoreML.def, AVFoundation.def, etc.)
- [ ] Compiles without errors

### 5.2 CoreML Mode Test
```bash
cd voice/pipelines/kmp
./gradlew linkReleaseExecutableMacos
./build/bin/macos/releaseExecutable/kmp-voice-pipeline.kexe
```

- [ ] VAD model loads (`silero-vad.mlmodelc`)
- [ ] ASR model loads (`sensevoice-500-itn.mlmodelc`)
- [ ] Speaker model loads (`xvector.mlmodelc`)
- [ ] Audio capture starts
- [ ] Live transcription works

### 5.3 ONNX Mode Test (if enabled)
```bash
./build/bin/macos/releaseExecutable/kmp-voice-pipeline.kexe --onnx
```

- [ ] ONNX Runtime initializes
- [ ] VAD model loads (`silero_vad.onnx`)
- [ ] (ASR ONNX may be broken - document status)

### 5.4 Path Verification
Check Main.kt contains correct paths:
```kotlin
// Should reference:
// models/coreml/
// models/onnx/
// models/assets/
// data/voice_library_xvector.json
```

- [ ] MODEL_DIR points to `voice/models/coreml`
- [ ] ONNX_MODEL_DIR points to `voice/models/onnx`
- [ ] ASSETS_DIR points to `voice/models/assets`
- [ ] VOICE_LIBRARY_PATH points to `voice/data/`

---

## 6. Model Files Verification

### 6.1 CoreML Models
```bash
ls -la voice/models/coreml/
```

Required:
- [ ] `silero-vad.mlmodelc/` (VAD)
- [ ] `sensevoice-500-itn.mlmodelc/` (ASR with ITN)
- [ ] `xvector.mlmodelc/` (Speaker embedding)

Optional:
- [ ] `ecapa.mlmodelc/` (Alternative speaker model)
- [ ] `SepReformer_Base.mlpackage/` (Speech separation)

### 6.2 ONNX Models
```bash
ls -la voice/models/onnx/
```

- [ ] `silero_vad.onnx` (VAD - works)
- [ ] `sensevoice.onnx` (ASR - check if working)
- [ ] `xvector.onnx` (Speaker - check if working)

### 6.3 Assets
```bash
ls -la voice/models/assets/
```

- [ ] `chn_jpn_yue_eng_ko_spectok.bpe.model` (SentencePiece tokenizer)
- [ ] `vocab.txt` or similar
- [ ] `filterbank.bin` (mel filterbank, if used)

---

## 7. Data Files

### 7.1 Voice Library
```bash
ls -la voice/data/
```

- [ ] `voice_library_xvector.json` exists (or created on first run)
- [ ] `recordings/` directory exists for storing audio

---

## 8. Performance Benchmarks

### 8.1 CoreML Inference Speed
Run with release build and compare:

| Model | Expected | Actual | Status |
|-------|----------|--------|--------|
| VAD (256ms chunk) | <20ms | ___ms | [ ] |
| ASR (3s audio) | <100ms | ___ms | [ ] |
| Speaker ID (3s audio) | <50ms | ___ms | [ ] |

### 8.2 End-to-End Latency
- [ ] Speech to text output < 500ms

---

## 9. Cross-Pipeline Consistency

Test same audio file across all pipelines:

```bash
# Python
python pipelines/python/transcription/live_transcription.py --file test.wav

# Swift
cd pipelines/swift && swift run VoicePipelineTest --file ../../test.wav

# KMP
./pipelines/kmp/build/bin/macos/releaseExecutable/kmp-voice-pipeline.kexe --file test.wav
```

- [ ] Same audio produces similar transcription across pipelines
- [ ] Speaker IDs match across pipelines (if library synced)

---

## 10. Known Issues

Document any known issues discovered during testing:

| Issue | Affected Component | Status |
|-------|-------------------|--------|
| ONNX ASR model outputs wrong shape (512 vs 25055) | KMP ONNX mode | Open |
| ONNX ASR/Speaker models not converted (only VAD) | ONNX models | Need conversion |
| mel_filterbank.bin is gitignored, must be copied manually | All pipelines | Manual step |
| Java 17+ required for KMP build | KMP pipeline | Checked in setup.sh |

---

## Quick Verification Command

One-liner to verify basic structure:

```bash
cd voice && \
  ls models/coreml/*.mlmodelc models/onnx/*.onnx 2>/dev/null | wc -l && \
  python scripts/convert.py --help 2>&1 | head -1 && \
  echo "Structure OK"
```

Expected: Shows model count, help text, "Structure OK"

---

## Sign-off

| Date | Tester | All Passed | Notes |
|------|--------|------------|-------|
| | | [ ] | |
