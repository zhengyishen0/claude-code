#!/usr/bin/env python3
"""
SenseVoice CoreML - Production-ready speech recognition.

Fast speech recognition using SenseVoice converted to CoreML for Apple Silicon.
Supports Chinese, English, Japanese, Korean, and Cantonese.
"""

import numpy as np
import coremltools as ct
import sentencepiece as spm
from pathlib import Path
import time
import re

# Audio processing
import torch
import torchaudio
import soundfile as sf


class SenseVoiceCoreML:
    """Production-ready SenseVoice using CoreML."""

    # Audio config
    SAMPLE_RATE = 16000
    N_MELS = 80
    N_FFT = 400       # 25ms at 16kHz
    HOP_LENGTH = 160  # 10ms at 16kHz
    LFR_M = 7  # stack this many frames
    LFR_N = 6  # skip this many frames

    # Fixed frame count for fast ANE inference
    FIXED_FRAMES = 250  # ~15s of audio

    # Chunking config for long audio
    # Each LFR frame = 6 * 10ms = 60ms, so 250 frames = 15s
    CHUNK_SECONDS = 14  # Slightly less than max to be safe
    OVERLAP_SECONDS = 1  # Overlap between chunks to avoid cutting words

    def __init__(self, model_dir: str = None, frames: int = 250):
        """
        Initialize SenseVoice CoreML.

        Args:
            model_dir: Directory containing models/ and pytorch/ subdirs.
                      If None, uses the directory containing this file.
            frames: Frame count for model (150, 250, 500, 750, 1000, 1500, 2000).
                   250 is recommended for most use cases.
        """
        if model_dir is None:
            self.model_dir = Path(__file__).parent
        else:
            self.model_dir = Path(model_dir)

        self.FIXED_FRAMES = frames
        # Update chunk settings based on frame count
        self.CHUNK_SECONDS = int(frames * 0.06) - 1  # ~60ms per frame, -1s safety

        print(f"Loading SenseVoice CoreML ({frames} frames)...")
        start = time.time()

        # Load CoreML model
        model_path = self.model_dir / "models" / f"sensevoice-{frames}.mlpackage"
        self.model = ct.models.MLModel(str(model_path))

        # Load tokenizer
        tokenizer_path = self.model_dir / "pytorch" / "chn_jpn_yue_eng_ko_spectok.bpe.model"
        self.tokenizer = spm.SentencePieceProcessor()
        self.tokenizer.load(str(tokenizer_path))

        # Setup mel spectrogram transform (torchaudio is 800x faster than librosa)
        self.mel_transform = torchaudio.transforms.MelSpectrogram(
            sample_rate=self.SAMPLE_RATE,
            n_mels=self.N_MELS,
            n_fft=self.N_FFT,
            hop_length=self.HOP_LENGTH,
            win_length=self.N_FFT,
            window_fn=torch.hamming_window,
            power=1.0
        )

        # Warmup
        self._warmup()

        print(f"  Loaded in {time.time() - start:.2f}s")

    def _warmup(self):
        """Warmup CoreML model for consistent timing."""
        dummy = np.random.randn(1, self.FIXED_FRAMES, 560).astype(np.float32)
        for _ in range(2):
            self.model.predict({"audio_features": dummy})

    def _compute_features(self, audio: np.ndarray) -> np.ndarray:
        """
        Compute LFR features from audio.

        Args:
            audio: Audio samples at 16kHz

        Returns:
            LFR features of shape (n_frames, 560)
        """
        # Compute mel spectrogram with torchaudio (800x faster than librosa)
        audio_t = torch.from_numpy(audio).unsqueeze(0)
        mel = self.mel_transform(audio_t)  # (1, n_mels, time)

        # Log scale and transpose to (time, mel)
        mel = torch.log(torch.clamp(mel, min=1e-10))
        mel = mel.squeeze(0).T.numpy().astype(np.float32)  # (time, n_mels)

        # Apply LFR (stack 7 frames, skip 6)
        lfr_frames = []
        for i in range(0, mel.shape[0], self.LFR_N):
            if i + self.LFR_M <= mel.shape[0]:
                stacked = mel[i:i + self.LFR_M].flatten()
                lfr_frames.append(stacked)

        if not lfr_frames:
            # Handle very short audio - pad mel first
            if mel.shape[0] < self.LFR_M:
                mel = np.pad(mel, ((0, self.LFR_M - mel.shape[0]), (0, 0)), mode='edge')
            stacked = mel[:self.LFR_M].flatten()
            lfr_frames.append(stacked)

        return np.array(lfr_frames, dtype=np.float32)

    def _pad_or_truncate(self, features: np.ndarray) -> np.ndarray:
        """Pad or truncate features to FIXED_FRAMES."""
        n_frames = features.shape[0]
        if n_frames < self.FIXED_FRAMES:
            padding = np.zeros((self.FIXED_FRAMES - n_frames, 560), dtype=np.float32)
            return np.concatenate([features, padding], axis=0)
        elif n_frames > self.FIXED_FRAMES:
            return features[:self.FIXED_FRAMES]
        return features

    def _ctc_greedy_decode(self, logits: np.ndarray) -> str:
        """
        Greedy CTC decoding.

        Args:
            logits: Output logits of shape (1, time, vocab_size)

        Returns:
            Decoded text
        """
        # Get most likely tokens
        tokens = np.argmax(logits[0], axis=-1)

        # Remove consecutive duplicates and blanks (blank = 0)
        decoded = []
        prev_token = -1
        for token in tokens:
            if token != 0 and token != prev_token:
                decoded.append(int(token))
            prev_token = token

        # Convert tokens to text
        text = self.tokenizer.decode(decoded)

        # Clean up special tokens
        text = self._clean_text(text)

        return text

    def _clean_text(self, text: str) -> str:
        """Remove special tokens and clean up text."""
        # Remove special tokens like <|zh|>, <|en|>, <|NEUTRAL|>, etc.
        text = re.sub(r'<\|[^|]+\|>', '', text)
        # Remove extra whitespace
        text = ' '.join(text.split())
        return text.strip()

    def transcribe(self, audio_path: str) -> tuple[str, float]:
        """
        Transcribe audio file to text.

        Args:
            audio_path: Path to audio file (WAV format)

        Returns:
            (transcript, elapsed_time_seconds)
        """
        start = time.time()

        # Load audio with soundfile (1000x faster than librosa for pcm_s32le)
        audio, sr = sf.read(audio_path)
        audio = audio.astype(np.float32)
        if sr != self.SAMPLE_RATE:
            audio_t = torch.from_numpy(audio)
            audio = torchaudio.functional.resample(audio_t, sr, self.SAMPLE_RATE).numpy()

        # Get transcript
        text = self._transcribe_audio(audio)

        elapsed = time.time() - start
        return text, elapsed

    def _transcribe_chunk(self, audio: np.ndarray) -> str:
        """Transcribe a single audio chunk (must fit within FIXED_FRAMES)."""
        # Compute features
        features = self._compute_features(audio)

        # Pad/truncate to fixed size for fast ANE inference
        features = self._pad_or_truncate(features)

        # Add batch dimension
        features = features[np.newaxis, :, :]

        # Run inference
        result = self.model.predict({"audio_features": features})
        logits = result["logits"]

        # Decode
        text = self._ctc_greedy_decode(logits)

        return text

    def _transcribe_audio(self, audio: np.ndarray) -> str:
        """
        Transcribe audio array, automatically chunking if longer than model capacity.

        For audio longer than CHUNK_SECONDS, splits into overlapping chunks,
        transcribes each, and concatenates results.
        """
        chunk_samples = int(self.CHUNK_SECONDS * self.SAMPLE_RATE)
        overlap_samples = int(self.OVERLAP_SECONDS * self.SAMPLE_RATE)
        step_samples = chunk_samples - overlap_samples

        # Short audio: process directly
        if len(audio) <= chunk_samples:
            return self._transcribe_chunk(audio)

        # Long audio: chunk and concatenate
        transcripts = []
        pos = 0

        while pos < len(audio):
            # Extract chunk
            end = min(pos + chunk_samples, len(audio))
            chunk = audio[pos:end]

            # Transcribe chunk
            text = self._transcribe_chunk(chunk)
            if text:
                transcripts.append(text)

            # Move to next chunk
            pos += step_samples

            # If remaining audio is too short, break
            if pos >= len(audio):
                break

        # Concatenate transcripts
        # For CJK languages, no space needed; for others, use space
        full_text = ' '.join(transcripts)

        return full_text

    def transcribe_audio(self, audio: np.ndarray) -> tuple[str, float]:
        """
        Transcribe audio array to text.

        Args:
            audio: Audio samples at 16kHz as numpy array

        Returns:
            (transcript, elapsed_time_seconds)
        """
        start = time.time()
        text = self._transcribe_audio(audio)
        elapsed = time.time() - start
        return text, elapsed


def test():
    """Test the SenseVoice CoreML model."""
    model = SenseVoiceCoreML()

    test_files = [
        ("Chinese (14s)", model.model_dir / "test" / "chinese-14s.wav"),
        ("English (31s)", model.model_dir / "test" / "english-31s.wav"),
    ]

    for name, path in test_files:
        if path.exists():
            print(f"\n=== {name} ===")
            text, elapsed = model.transcribe(str(path))
            print(f"Time: {elapsed*1000:.0f}ms")
            print(f"Text: {text[:100]}{'...' if len(text) > 100 else ''}")
        else:
            print(f"\n=== {name} === (file not found: {path})")


if __name__ == "__main__":
    test()
