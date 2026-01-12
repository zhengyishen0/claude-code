#!/usr/bin/env python3
"""
Full transcription with SentencePiece decoding for Python vs Swift comparison.
"""
import torch
import torchaudio
import numpy as np
import time
import sys
from pathlib import Path

# Try to import sentencepiece
try:
    import sentencepiece as spm
    HAS_SPM = True
except ImportError:
    HAS_SPM = False
    print("Warning: sentencepiece not installed, will show token IDs only")

# Configuration
SAMPLE_RATE = 16000
N_MELS = 80
N_FFT = 400
HOP_LENGTH = 160
LFR_M = 7
LFR_N = 6
FIXED_FRAMES = 500

# Special token IDs for SenseVoice
LANG_TOKENS = {
    24884: "auto",
    24885: "zh",
    24886: "en",
    24887: "yue",
    24888: "ja",
    24889: "ko",
}

TASK_TOKENS = {
    25004: "transcribe",
    25005: "translate",
}

EMOTION_TOKENS = {
    24993: "NEUTRAL",
    24994: "HAPPY",
    24995: "SAD",
    24996: "ANGRY",
}

EVENT_TOKENS = {
    25016: "Speech",
    25017: "Applause",
    25018: "BGM",
    25019: "Laughter",
}

def apply_lfr(mel):
    """Apply LFR transform."""
    T = mel.shape[0]
    lfr_frames = []
    i = 0
    while i + LFR_M <= T:
        frame = mel[i:i+LFR_M].reshape(-1)
        lfr_frames.append(frame)
        i += LFR_N
    if lfr_frames:
        return np.stack(lfr_frames)
    return np.array([])

def pad_to_fixed(features, fixed_frames=500):
    """Pad or truncate to fixed number of frames."""
    if len(features) < fixed_frames:
        padding = np.zeros((fixed_frames - len(features), features.shape[1]), dtype=np.float32)
        return np.vstack([features, padding])
    return features[:fixed_frames]

def decode_special_tokens(tokens):
    """Decode special tokens (language, task, emotion, event)."""
    info = {}
    text_tokens = []

    for i, tok in enumerate(tokens):
        if tok in LANG_TOKENS:
            info['language'] = LANG_TOKENS[tok]
        elif tok in TASK_TOKENS:
            info['task'] = TASK_TOKENS[tok]
        elif tok in EMOTION_TOKENS:
            info['emotion'] = EMOTION_TOKENS[tok]
        elif tok in EVENT_TOKENS:
            info['event'] = EVENT_TOKENS[tok]
        else:
            text_tokens.append(tok)

    return info, text_tokens

def transcribe(audio_path, model, tokenizer=None):
    """Full transcription pipeline."""
    print(f"\n{'='*60}")
    print(f"Transcribing: {Path(audio_path).name}")
    print('='*60)

    start_total = time.time()

    # Load audio
    waveform, sample_rate = torchaudio.load(audio_path)
    if waveform.shape[0] > 1:
        waveform = waveform.mean(dim=0, keepdim=True)
    if sample_rate != SAMPLE_RATE:
        resampler = torchaudio.transforms.Resample(sample_rate, SAMPLE_RATE)
        waveform = resampler(waveform)

    audio_duration = waveform.shape[1] / SAMPLE_RATE
    print(f"Audio duration: {audio_duration:.2f}s")

    # Mel spectrogram
    mel_transform = torchaudio.transforms.MelSpectrogram(
        sample_rate=SAMPLE_RATE,
        n_mels=N_MELS,
        n_fft=N_FFT,
        hop_length=HOP_LENGTH,
        win_length=N_FFT,
        window_fn=torch.hamming_window,
        power=1.0,
        center=True,
        pad_mode='reflect'
    )

    mel = mel_transform(waveform)
    mel_numpy = mel.squeeze(0).T.numpy()

    # Log transform
    log_mel = np.log(np.clip(mel_numpy, a_min=1e-10, a_max=None))

    # LFR
    lfr = apply_lfr(log_mel)

    # Pad
    padded = pad_to_fixed(lfr, FIXED_FRAMES)

    # CoreML inference
    input_dict = {'audio_features': padded.reshape(1, 500, 560).astype(np.float32)}
    output = model.predict(input_dict)
    logits = output['logits']

    # CTC decode
    tokens = []
    prev_token = -1
    for t in range(logits.shape[1]):
        max_idx = np.argmax(logits[0, t, :])
        if max_idx != 0 and max_idx != prev_token:
            tokens.append(int(max_idx))
        prev_token = max_idx

    total_time = (time.time() - start_total) * 1000

    # Decode special tokens
    info, text_tokens = decode_special_tokens(tokens)

    print(f"\nResults:")
    print(f"  Language: {info.get('language', 'unknown')}")
    print(f"  Task: {info.get('task', 'unknown')}")
    print(f"  Emotion: {info.get('emotion', 'unknown')}")
    print(f"  Event: {info.get('event', 'unknown')}")
    print(f"  Token count: {len(tokens)} (text tokens: {len(text_tokens)})")
    print(f"  Processing time: {total_time:.0f}ms")

    # Decode text if tokenizer available
    if tokenizer and text_tokens:
        text = tokenizer.decode(text_tokens)
        print(f"\n  Transcription: {text}")
    else:
        print(f"\n  Token IDs: {text_tokens[:30]}...")

    return {
        'audio_path': str(audio_path),
        'duration': audio_duration,
        'language': info.get('language'),
        'emotion': info.get('emotion'),
        'event': info.get('event'),
        'tokens': tokens,
        'text_tokens': text_tokens,
        'time_ms': total_time,
    }

def main():
    import coremltools as ct

    # Load model (from main branch - use mlpackage for Python)
    model_path = "/Users/zhengyishen/Codes/claude-code/voice/transcription/models/sensevoice-500-itn.mlpackage"
    print("Loading CoreML model...")
    model = ct.models.MLModel(model_path)

    # Load tokenizer (from main branch)
    tokenizer = None
    if HAS_SPM:
        tokenizer_path = "/Users/zhengyishen/Codes/claude-code/voice/transcription/pytorch/chn_jpn_yue_eng_ko_spectok.bpe.model"
        if Path(tokenizer_path).exists():
            tokenizer = spm.SentencePieceProcessor()
            tokenizer.load(tokenizer_path)
            print(f"Loaded tokenizer: {tokenizer.get_piece_size()} tokens")

    # Audio files to transcribe
    audio_files = [
        "/Users/zhengyishen/Codes/claude-code/voice/recordings/sample.wav",
        "/Users/zhengyishen/Codes/claude-code/voice/recordings/test_recording.wav",
    ]

    results = []
    for audio_path in audio_files:
        if Path(audio_path).exists():
            result = transcribe(audio_path, model, tokenizer)
            results.append(result)
        else:
            print(f"File not found: {audio_path}")

    # Summary
    print("\n" + "="*60)
    print("PYTHON TRANSCRIPTION SUMMARY")
    print("="*60)
    for r in results:
        print(f"\n{Path(r['audio_path']).name}:")
        print(f"  Duration: {r['duration']:.2f}s")
        print(f"  Language: {r['language']}, Emotion: {r['emotion']}")
        print(f"  Tokens: {len(r['tokens'])}")
        print(f"  Time: {r['time_ms']:.0f}ms")

if __name__ == '__main__':
    main()
