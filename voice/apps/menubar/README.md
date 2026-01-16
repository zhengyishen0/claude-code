# Voice Translator Menu Bar App

A minimal macOS menu bar utility for push-to-talk voice transcription.

## Features

- **Push-to-talk**: Hold hotkey to record, release to transcribe
- **Multiple ASR models**: SenseVoice (zh/en), Whisper Turbo (99 langs), Parakeet (en)
- **Configurable hotkey**: Set your own key combination
- **History**: Last 3 transcriptions cached, Ctrl+Shift+V to cycle

## Usage

1. Click the mic icon in menu bar to select ASR model
2. Hold your configured hotkey (default: Option) to record
3. Release to transcribe - text is auto-pasted at cursor
4. Use Ctrl+Shift+V to paste from history

## Build

```bash
cd voice/apps/menubar
swift build -c release
```

## Requirements

- macOS 13+
- KMP pipeline built (`voice/pipelines/kmp/build/bin/macosArm64/releaseExecutable/kmp-pipeline.kexe`)
- CoreML models in the models directory

## Permissions

- Microphone access (for recording)
- Accessibility (for hotkeys and paste simulation)
