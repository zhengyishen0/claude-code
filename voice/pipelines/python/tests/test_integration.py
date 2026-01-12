#!/usr/bin/env python3
"""
Integration tests for voice pipeline components.

Tests that individual components connect and communicate correctly.
"""

import numpy as np
import pytest
from pathlib import Path
import soundfile as sf
import torchaudio.functional as F
import torch

# Test audio paths
VOICE_DIR = Path(__file__).parent.parent
TEST_AUDIO_DIR = VOICE_DIR / "separation" / "test_audio"
TRANSCRIPTION_TEST_DIR = VOICE_DIR / "transcription" / "test"


def resample(audio: np.ndarray, orig_sr: int, target_sr: int) -> np.ndarray:
    """Resample audio using torchaudio."""
    if orig_sr == target_sr:
        return audio
    audio_tensor = torch.from_numpy(audio).float()
    resampled = F.resample(audio_tensor, orig_sr, target_sr)
    return resampled.numpy()


class TestSampleRateConversion:
    """Test sample rate conversion between components."""

    def test_resample_16k_to_8k(self):
        """Test downsampling from 16kHz to 8kHz."""
        # Create 1 second of 16kHz audio
        audio_16k = np.random.randn(16000).astype(np.float32)
        audio_8k = resample(audio_16k, 16000, 8000)

        assert len(audio_8k) == 8000
        assert audio_8k.dtype == np.float32

    def test_resample_8k_to_16k(self):
        """Test upsampling from 8kHz to 16kHz."""
        # Create 1 second of 8kHz audio
        audio_8k = np.random.randn(8000).astype(np.float32)
        audio_16k = resample(audio_8k, 8000, 16000)

        assert len(audio_16k) == 16000
        assert audio_16k.dtype == np.float32

    def test_resample_roundtrip(self):
        """Test that 16k -> 8k -> 16k preserves signal."""
        audio_16k = np.sin(2 * np.pi * 440 * np.arange(16000) / 16000).astype(np.float32)
        audio_8k = resample(audio_16k, 16000, 8000)
        audio_16k_back = resample(audio_8k, 8000, 16000)

        # Should have same length
        assert len(audio_16k_back) == len(audio_16k)
        # Correlation should be high (signal preserved)
        correlation = np.corrcoef(audio_16k, audio_16k_back)[0, 1]
        assert correlation > 0.9


class TestSeparationToVAD:
    """Test that separation output works with VAD."""

    @pytest.fixture
    def separation_model(self):
        """Load separation model."""
        import coremltools as ct
        model_path = VOICE_DIR / "separation" / "models" / "SepReformer_Base.mlpackage"
        if not model_path.exists():
            pytest.skip(f"Separation model not found: {model_path}")
        return ct.models.MLModel(str(model_path))

    @pytest.fixture
    def vad(self):
        """Load VAD."""
        from voice.vad import SileroVAD
        return SileroVAD()

    def test_separated_audio_works_with_vad(self, separation_model, vad):
        """Verify separated audio streams work with VAD."""
        # Load test mixture
        mixture_path = TEST_AUDIO_DIR / "osr_mixture_33s.wav"
        if not mixture_path.exists():
            pytest.skip(f"Test audio not found: {mixture_path}")

        audio, sr = sf.read(str(mixture_path))
        audio = audio.astype(np.float32)

        # Resample to 8kHz for separation
        audio_8k = resample(audio, sr, 8000)

        # Separate (first 4 seconds only for speed)
        chunk = audio_8k[:32000].reshape(1, -1)
        output = separation_model.predict({"audio_input": chunk})

        speaker1 = output["speaker1"].flatten()
        speaker2 = output["speaker2"].flatten()

        # Resample back to 16kHz for VAD
        speaker1_16k = resample(speaker1, 8000, 16000)
        speaker2_16k = resample(speaker2, 8000, 16000)

        # Run VAD on both streams
        segments1 = vad.detect_speech(speaker1_16k, sample_rate=16000)
        segments2 = vad.detect_speech(speaker2_16k, sample_rate=16000)

        # Should detect some speech in at least one stream
        assert len(segments1) > 0 or len(segments2) > 0


class TestVADToTranscription:
    """Test that VAD output works with transcription."""

    @pytest.fixture
    def vad(self):
        """Load VAD."""
        from voice.vad import SileroVAD
        return SileroVAD()

    @pytest.fixture
    def transcriber(self):
        """Load transcription model."""
        from voice.transcription.sensevoice_coreml import SenseVoiceCoreML
        return SenseVoiceCoreML(frames=500, itn=True)

    def test_vad_segments_transcribe_correctly(self, vad, transcriber):
        """Verify VAD-detected segments transcribe correctly."""
        # Load test audio
        audio_path = TRANSCRIPTION_TEST_DIR / "chinese-14s.wav"
        if not audio_path.exists():
            pytest.skip(f"Test audio not found: {audio_path}")

        audio, sr = sf.read(str(audio_path))
        audio = audio.astype(np.float32)

        # Resample to 16kHz if needed
        if sr != 16000:
            audio = resample(audio, sr, 16000)

        # Detect speech segments
        segments = vad.detect_speech(audio, sample_rate=16000)
        assert len(segments) > 0, "VAD should detect speech"

        # Transcribe first segment
        start_time, end_time = segments[0]
        start_sample = int(start_time * 16000)
        end_sample = int(end_time * 16000)
        segment_audio = audio[start_sample:end_sample]

        # Transcribe
        text, elapsed = transcriber.transcribe_audio(segment_audio)

        assert len(text) > 0, "Transcription should produce text"
        assert elapsed > 0, "Transcription should take time"


class TestVADToSpeakerID:
    """Test that VAD output works with speaker ID."""

    @pytest.fixture
    def vad(self):
        """Load VAD."""
        from voice.vad import SileroVAD
        return SileroVAD()

    @pytest.fixture
    def speaker_id(self):
        """Load speaker ID."""
        from voice.speaker_id import SpeakerID
        return SpeakerID()

    def test_vad_segments_produce_embeddings(self, vad, speaker_id):
        """Verify VAD-detected segments produce valid speaker embeddings."""
        # Load test audio
        audio_path = TRANSCRIPTION_TEST_DIR / "chinese-14s.wav"
        if not audio_path.exists():
            pytest.skip(f"Test audio not found: {audio_path}")

        audio, sr = sf.read(str(audio_path))
        audio = audio.astype(np.float32)

        # Resample to 16kHz if needed
        if sr != 16000:
            audio = resample(audio, sr, 16000)

        # Detect speech segments
        segments = vad.detect_speech(audio, sample_rate=16000)
        assert len(segments) > 0, "VAD should detect speech"

        # Extract embedding from first segment
        start_time, end_time = segments[0]
        start_sample = int(start_time * 16000)
        end_sample = int(end_time * 16000)
        segment_audio = audio[start_sample:end_sample]

        # Get embedding
        embedding = speaker_id.extract_embedding(segment_audio, sample_rate=16000)

        assert embedding is not None
        assert len(embedding) == 192  # ECAPA-TDNN produces 192-dim embeddings


class TestSpeakerIDMatching:
    """Test speaker ID enrollment and matching."""

    @pytest.fixture
    def speaker_id(self):
        """Load speaker ID."""
        from voice.speaker_id import SpeakerID
        return SpeakerID()

    def test_enroll_and_identify(self, speaker_id):
        """Test enrolling a speaker and identifying them."""
        # Load male and female audio for enrollment
        male_path = TEST_AUDIO_DIR / "osr_male.wav"
        female_path = TEST_AUDIO_DIR / "osr_female.wav"

        if not male_path.exists() or not female_path.exists():
            pytest.skip("Test audio not found")

        male_audio, sr1 = sf.read(str(male_path))
        female_audio, sr2 = sf.read(str(female_path))

        male_audio = male_audio.astype(np.float32)
        female_audio = female_audio.astype(np.float32)

        # Resample if needed
        if sr1 != 16000:
            male_audio = resample(male_audio, sr1, 16000)
        if sr2 != 16000:
            female_audio = resample(female_audio, sr2, 16000)

        # Enroll speakers
        speaker_id.enroll("Male", male_audio, sample_rate=16000)
        speaker_id.enroll("Female", female_audio, sample_rate=16000)

        # Test identification with male audio
        identified, confidence = speaker_id.identify(male_audio[:16000*5], sample_rate=16000)
        assert identified == "Male", f"Expected 'Male', got '{identified}'"
        assert confidence > 0.5

        # Test identification with female audio
        identified, confidence = speaker_id.identify(female_audio[:16000*5], sample_rate=16000)
        assert identified == "Female", f"Expected 'Female', got '{identified}'"
        assert confidence > 0.5


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
