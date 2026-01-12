#!/usr/bin/env python3
"""
Voice Activity Detection (VAD) module for the voice pipeline.

Supports multiple backends:
1. Silero VAD (PyTorch) - Default, good accuracy, ~2MB
2. Silero VAD (ONNX) - Faster inference, cross-platform
3. CoreML VAD - Native Apple Silicon acceleration (TODO)
4. WebRTC VAD - Fastest, rule-based, less accurate

Usage:
    vad = SileroVAD()  # or VADFactory.create("silero")
    segments = vad.detect_speech(audio, sample_rate=16000)
    # Returns: [(start_sec, end_sec), ...]

For CoreML conversion:
    vad = SileroVAD(use_onnx=True)
    vad.export_onnx("silero_vad.onnx")
    # Then convert: coremltools.converters.onnx.convert("silero_vad.onnx")
"""

import torch
import numpy as np
from typing import List, Tuple, Optional, Union
from pathlib import Path
from abc import ABC, abstractmethod


class BaseVAD(ABC):
    """Abstract base class for VAD implementations."""

    @abstractmethod
    def detect_speech(
        self,
        audio: np.ndarray,
        sample_rate: int = 16000
    ) -> List[Tuple[float, float]]:
        """Detect speech segments in audio."""
        pass

    @abstractmethod
    def detect_speech_probs(
        self,
        audio: np.ndarray,
        sample_rate: int = 16000
    ) -> np.ndarray:
        """Get frame-level speech probabilities."""
        pass


class SileroVAD(BaseVAD):
    """
    Silero VAD wrapper for speech detection.

    The model runs on CPU and is very lightweight (~2MB).
    It processes audio in chunks and returns speech segments.
    """

    def __init__(
        self,
        threshold: float = 0.5,
        min_speech_duration_ms: int = 250,
        min_silence_duration_ms: int = 100,
        window_size_samples: int = 512,
        speech_pad_ms: int = 30,
    ):
        """
        Initialize Silero VAD.

        Args:
            threshold: Speech probability threshold (0-1)
            min_speech_duration_ms: Minimum speech segment duration
            min_silence_duration_ms: Minimum silence to split segments
            window_size_samples: Processing window size (512 for 16kHz)
            speech_pad_ms: Padding around speech segments
        """
        self.threshold = threshold
        self.min_speech_duration_ms = min_speech_duration_ms
        self.min_silence_duration_ms = min_silence_duration_ms
        self.window_size_samples = window_size_samples
        self.speech_pad_ms = speech_pad_ms

        # Load model
        self.model, self.utils = torch.hub.load(
            repo_or_dir='snakers4/silero-vad',
            model='silero_vad',
            force_reload=False,
            onnx=False
        )
        self.model.eval()

        # Get utility functions
        (
            self.get_speech_timestamps,
            self.save_audio,
            self.read_audio,
            self.VADIterator,
            self.collect_chunks
        ) = self.utils

        # Supported sample rates
        self.supported_sample_rates = [8000, 16000]

    def detect_speech(
        self,
        audio: np.ndarray,
        sample_rate: int = 16000
    ) -> List[Tuple[float, float]]:
        """
        Detect speech segments in audio.

        Args:
            audio: Audio samples as numpy array (mono, float32)
            sample_rate: Sample rate (8000 or 16000 Hz)

        Returns:
            List of (start_seconds, end_seconds) tuples for each speech segment
        """
        if sample_rate not in self.supported_sample_rates:
            raise ValueError(f"Sample rate must be {self.supported_sample_rates}, got {sample_rate}")

        # Convert to torch tensor
        if isinstance(audio, np.ndarray):
            audio_tensor = torch.from_numpy(audio).float()
        else:
            audio_tensor = audio.float()

        # Ensure 1D
        if audio_tensor.dim() > 1:
            audio_tensor = audio_tensor.squeeze()

        # Get speech timestamps
        speech_timestamps = self.get_speech_timestamps(
            audio_tensor,
            self.model,
            sampling_rate=sample_rate,
            threshold=self.threshold,
            min_speech_duration_ms=self.min_speech_duration_ms,
            min_silence_duration_ms=self.min_silence_duration_ms,
            window_size_samples=self.window_size_samples,
            speech_pad_ms=self.speech_pad_ms,
            return_seconds=False  # Return samples
        )

        # Convert to seconds
        segments = []
        for ts in speech_timestamps:
            start_sec = ts['start'] / sample_rate
            end_sec = ts['end'] / sample_rate
            segments.append((start_sec, end_sec))

        return segments

    def detect_speech_probs(
        self,
        audio: np.ndarray,
        sample_rate: int = 16000
    ) -> np.ndarray:
        """
        Get frame-level speech probabilities.

        Args:
            audio: Audio samples as numpy array
            sample_rate: Sample rate (8000 or 16000 Hz)

        Returns:
            Array of speech probabilities for each frame
        """
        if sample_rate not in self.supported_sample_rates:
            raise ValueError(f"Sample rate must be {self.supported_sample_rates}, got {sample_rate}")

        # Convert to torch tensor
        if isinstance(audio, np.ndarray):
            audio_tensor = torch.from_numpy(audio).float()
        else:
            audio_tensor = audio.float()

        # Ensure 1D
        if audio_tensor.dim() > 1:
            audio_tensor = audio_tensor.squeeze()

        # Process in windows
        probs = []
        self.model.reset_states()

        for i in range(0, len(audio_tensor), self.window_size_samples):
            chunk = audio_tensor[i:i + self.window_size_samples]
            if len(chunk) < self.window_size_samples:
                # Pad last chunk
                chunk = torch.nn.functional.pad(
                    chunk, (0, self.window_size_samples - len(chunk))
                )

            prob = self.model(chunk, sample_rate)
            probs.append(prob.item())

        return np.array(probs)

    def extract_speech_audio(
        self,
        audio: np.ndarray,
        sample_rate: int = 16000
    ) -> Tuple[np.ndarray, List[Tuple[float, float]]]:
        """
        Extract only speech portions from audio.

        Args:
            audio: Audio samples as numpy array
            sample_rate: Sample rate

        Returns:
            Tuple of (concatenated_speech_audio, segments)
        """
        segments = self.detect_speech(audio, sample_rate)

        if not segments:
            return np.array([]), []

        # Extract speech chunks
        speech_chunks = []
        for start_sec, end_sec in segments:
            start_sample = int(start_sec * sample_rate)
            end_sample = int(end_sec * sample_rate)
            speech_chunks.append(audio[start_sample:end_sample])

        # Concatenate
        speech_audio = np.concatenate(speech_chunks)

        return speech_audio, segments


class VADIterator:
    """
    Streaming VAD iterator for real-time processing.

    Processes audio in small chunks and yields speech segments
    as they are detected.
    """

    def __init__(
        self,
        vad: SileroVAD,
        sample_rate: int = 16000,
        frame_duration_ms: int = 32
    ):
        """
        Initialize streaming VAD.

        Args:
            vad: SileroVAD instance
            sample_rate: Sample rate
            frame_duration_ms: Frame duration for streaming
        """
        self.vad = vad
        self.sample_rate = sample_rate
        self.frame_duration_ms = frame_duration_ms
        self.frame_size = int(sample_rate * frame_duration_ms / 1000)

        # State
        self.buffer = np.array([], dtype=np.float32)
        self.is_speech = False
        self.speech_start = 0.0
        self.current_time = 0.0
        self.silence_frames = 0
        self.speech_frames = 0

        # Thresholds in frames
        self.min_speech_frames = int(vad.min_speech_duration_ms / frame_duration_ms)
        self.min_silence_frames = int(vad.min_silence_duration_ms / frame_duration_ms)

    def process_frame(self, frame: np.ndarray) -> Optional[Tuple[float, float]]:
        """
        Process a single audio frame.

        Args:
            frame: Audio frame

        Returns:
            (start, end) tuple if a segment ended, None otherwise
        """
        # Get speech probability
        self.vad.model.reset_states()
        frame_tensor = torch.from_numpy(frame).float()
        prob = self.vad.model(frame_tensor, self.sample_rate).item()

        is_speech_frame = prob >= self.vad.threshold
        result = None

        if is_speech_frame:
            self.speech_frames += 1
            self.silence_frames = 0

            if not self.is_speech and self.speech_frames >= self.min_speech_frames:
                # Speech started
                self.is_speech = True
                self.speech_start = self.current_time - (self.speech_frames * self.frame_duration_ms / 1000)
        else:
            self.silence_frames += 1

            if self.is_speech and self.silence_frames >= self.min_silence_frames:
                # Speech ended
                result = (self.speech_start, self.current_time)
                self.is_speech = False
                self.speech_frames = 0

        self.current_time += self.frame_duration_ms / 1000

        return result

    def reset(self):
        """Reset iterator state."""
        self.buffer = np.array([], dtype=np.float32)
        self.is_speech = False
        self.speech_start = 0.0
        self.current_time = 0.0
        self.silence_frames = 0
        self.speech_frames = 0


class WebRTCVAD(BaseVAD):
    """
    WebRTC VAD - fastest option, rule-based (not neural).

    Pros: Very fast, tiny, no ML framework needed
    Cons: Less accurate than neural VAD, no probability output
    """

    def __init__(
        self,
        aggressiveness: int = 3,
        frame_duration_ms: int = 30,
        min_speech_duration_ms: int = 250,
        min_silence_duration_ms: int = 100,
    ):
        """
        Initialize WebRTC VAD.

        Args:
            aggressiveness: 0-3, higher = more aggressive filtering
            frame_duration_ms: Frame size (10, 20, or 30 ms)
            min_speech_duration_ms: Minimum speech segment duration
            min_silence_duration_ms: Minimum silence to split segments
        """
        try:
            import webrtcvad
            self.vad = webrtcvad.Vad(aggressiveness)
        except ImportError:
            raise ImportError("webrtcvad not installed. Run: pip install webrtcvad")

        self.aggressiveness = aggressiveness
        self.frame_duration_ms = frame_duration_ms
        self.min_speech_duration_ms = min_speech_duration_ms
        self.min_silence_duration_ms = min_silence_duration_ms

    def detect_speech(
        self,
        audio: np.ndarray,
        sample_rate: int = 16000
    ) -> List[Tuple[float, float]]:
        """Detect speech using WebRTC VAD."""
        if sample_rate not in [8000, 16000, 32000, 48000]:
            raise ValueError(f"WebRTC VAD requires 8000/16000/32000/48000 Hz, got {sample_rate}")

        # Convert to 16-bit PCM
        audio_int16 = (audio * 32767).astype(np.int16)
        frame_size = int(sample_rate * self.frame_duration_ms / 1000)

        # Process frames
        is_speech_frames = []
        for i in range(0, len(audio_int16) - frame_size, frame_size):
            frame = audio_int16[i:i + frame_size].tobytes()
            is_speech = self.vad.is_speech(frame, sample_rate)
            is_speech_frames.append(is_speech)

        # Convert to segments
        segments = []
        in_speech = False
        speech_start = 0
        silence_frames = 0
        speech_frames = 0

        min_speech_frames = int(self.min_speech_duration_ms / self.frame_duration_ms)
        min_silence_frames = int(self.min_silence_duration_ms / self.frame_duration_ms)

        for i, is_speech in enumerate(is_speech_frames):
            time_sec = i * self.frame_duration_ms / 1000

            if is_speech:
                speech_frames += 1
                silence_frames = 0
                if not in_speech and speech_frames >= min_speech_frames:
                    in_speech = True
                    speech_start = time_sec - (speech_frames * self.frame_duration_ms / 1000)
            else:
                silence_frames += 1
                if in_speech and silence_frames >= min_silence_frames:
                    segments.append((speech_start, time_sec))
                    in_speech = False
                    speech_frames = 0

        # Handle trailing speech
        if in_speech:
            segments.append((speech_start, len(is_speech_frames) * self.frame_duration_ms / 1000))

        return segments

    def detect_speech_probs(
        self,
        audio: np.ndarray,
        sample_rate: int = 16000
    ) -> np.ndarray:
        """WebRTC VAD returns binary, so we return 0/1 probabilities."""
        if sample_rate not in [8000, 16000, 32000, 48000]:
            raise ValueError(f"WebRTC VAD requires 8000/16000/32000/48000 Hz")

        audio_int16 = (audio * 32767).astype(np.int16)
        frame_size = int(sample_rate * self.frame_duration_ms / 1000)

        probs = []
        for i in range(0, len(audio_int16) - frame_size, frame_size):
            frame = audio_int16[i:i + frame_size].tobytes()
            is_speech = self.vad.is_speech(frame, sample_rate)
            probs.append(1.0 if is_speech else 0.0)

        return np.array(probs)


class VADFactory:
    """Factory for creating VAD instances."""

    @staticmethod
    def create(
        backend: str = "silero",
        **kwargs
    ) -> BaseVAD:
        """
        Create a VAD instance.

        Args:
            backend: "silero", "webrtc", or "energy"
            **kwargs: Backend-specific arguments

        Returns:
            VAD instance
        """
        if backend == "silero":
            return SileroVAD(**kwargs)
        elif backend == "webrtc":
            return WebRTCVAD(**kwargs)
        elif backend == "energy":
            return EnergyVAD(**kwargs)
        else:
            raise ValueError(f"Unknown VAD backend: {backend}")

    @staticmethod
    def list_backends() -> List[str]:
        """List available VAD backends."""
        return ["silero", "webrtc", "energy"]


class EnergyVAD(BaseVAD):
    """
    Simple energy-based VAD - fastest, but least accurate.

    Uses RMS energy threshold to detect speech.
    Good as a pre-filter before more expensive VAD.
    """

    def __init__(
        self,
        energy_threshold: float = 0.01,
        frame_duration_ms: int = 30,
        min_speech_duration_ms: int = 250,
        min_silence_duration_ms: int = 100,
    ):
        self.energy_threshold = energy_threshold
        self.frame_duration_ms = frame_duration_ms
        self.min_speech_duration_ms = min_speech_duration_ms
        self.min_silence_duration_ms = min_silence_duration_ms

    def detect_speech(
        self,
        audio: np.ndarray,
        sample_rate: int = 16000
    ) -> List[Tuple[float, float]]:
        """Detect speech using energy threshold."""
        frame_size = int(sample_rate * self.frame_duration_ms / 1000)

        # Calculate RMS energy per frame
        energies = []
        for i in range(0, len(audio) - frame_size, frame_size):
            frame = audio[i:i + frame_size]
            rms = np.sqrt(np.mean(frame ** 2))
            energies.append(rms)

        # Convert to segments
        segments = []
        in_speech = False
        speech_start = 0
        silence_frames = 0
        speech_frames = 0

        min_speech_frames = int(self.min_speech_duration_ms / self.frame_duration_ms)
        min_silence_frames = int(self.min_silence_duration_ms / self.frame_duration_ms)

        for i, energy in enumerate(energies):
            time_sec = i * self.frame_duration_ms / 1000
            is_speech = energy >= self.energy_threshold

            if is_speech:
                speech_frames += 1
                silence_frames = 0
                if not in_speech and speech_frames >= min_speech_frames:
                    in_speech = True
                    speech_start = time_sec - (speech_frames * self.frame_duration_ms / 1000)
            else:
                silence_frames += 1
                if in_speech and silence_frames >= min_silence_frames:
                    segments.append((speech_start, time_sec))
                    in_speech = False
                    speech_frames = 0

        if in_speech:
            segments.append((speech_start, len(energies) * self.frame_duration_ms / 1000))

        return segments

    def detect_speech_probs(
        self,
        audio: np.ndarray,
        sample_rate: int = 16000
    ) -> np.ndarray:
        """Return normalized energy as probability."""
        frame_size = int(sample_rate * self.frame_duration_ms / 1000)

        energies = []
        for i in range(0, len(audio) - frame_size, frame_size):
            frame = audio[i:i + frame_size]
            rms = np.sqrt(np.mean(frame ** 2))
            energies.append(rms)

        energies = np.array(energies)
        # Normalize to 0-1 range
        if energies.max() > 0:
            energies = energies / energies.max()

        return energies


def test_vad():
    """Test VAD with synthetic audio."""
    print("Testing Silero VAD...")

    # Create VAD
    vad = SileroVAD()
    print("  Model loaded!")

    # Create test audio: silence + speech-like + silence
    sample_rate = 16000
    duration = 5.0

    # Generate test signal (sine wave as "speech", silence otherwise)
    t = np.linspace(0, duration, int(duration * sample_rate))
    audio = np.zeros_like(t, dtype=np.float32)

    # Add "speech" from 1.0s to 2.5s and 3.0s to 4.0s
    speech_1_start, speech_1_end = 1.0, 2.5
    speech_2_start, speech_2_end = 3.0, 4.0

    # Use multiple frequencies to simulate speech
    for freq in [200, 400, 600, 800]:
        mask1 = (t >= speech_1_start) & (t <= speech_1_end)
        mask2 = (t >= speech_2_start) & (t <= speech_2_end)
        audio[mask1] += 0.1 * np.sin(2 * np.pi * freq * t[mask1])
        audio[mask2] += 0.1 * np.sin(2 * np.pi * freq * t[mask2])

    # Normalize
    audio = audio / np.abs(audio).max() * 0.5

    # Detect speech
    segments = vad.detect_speech(audio, sample_rate)

    print(f"  Test audio: {duration}s")
    print(f"  Expected speech: [{speech_1_start}-{speech_1_end}s], [{speech_2_start}-{speech_2_end}s]")
    print(f"  Detected segments: {segments}")

    # Get probabilities
    probs = vad.detect_speech_probs(audio, sample_rate)
    print(f"  Probability array shape: {probs.shape}")
    print(f"  Mean probability: {probs.mean():.3f}")

    print("  VAD test complete!")
    return True


if __name__ == "__main__":
    test_vad()
