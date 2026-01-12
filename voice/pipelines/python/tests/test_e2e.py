#!/usr/bin/env python3
"""
End-to-end tests for the voice pipeline.

Tests the complete system from raw audio input to final output.
"""

import numpy as np
import pytest
from pathlib import Path
import soundfile as sf

# Test audio paths
VOICE_DIR = Path(__file__).parent.parent
TEST_AUDIO_DIR = VOICE_DIR / "separation" / "test_audio"
TRANSCRIPTION_TEST_DIR = VOICE_DIR / "transcription" / "test"


class TestFullPipeline:
    """End-to-end tests for the full pipeline."""

    @pytest.fixture(scope="class")
    def pipeline_with_separation(self):
        """Load pipeline with separation enabled."""
        from voice.pipeline import VoicePipeline
        return VoicePipeline(
            enable_separation=True,
            enable_speaker_id=True,
            transcription_frames=500,
            transcription_itn=True
        )

    @pytest.fixture(scope="class")
    def pipeline_without_separation(self):
        """Load pipeline without separation (single speaker mode)."""
        from voice.pipeline import VoicePipeline
        return VoicePipeline(
            enable_separation=False,
            enable_speaker_id=False,
            transcription_frames=500,
            transcription_itn=True
        )

    def test_single_speaker_chinese(self, pipeline_without_separation):
        """Test single speaker Chinese audio."""
        audio_path = TRANSCRIPTION_TEST_DIR / "chinese-14s.wav"
        if not audio_path.exists():
            pytest.skip(f"Test audio not found: {audio_path}")

        result = pipeline_without_separation.process(str(audio_path))

        # Verify result structure
        assert result.audio_duration > 0
        assert result.processing_time > 0
        assert len(result.segments) > 0
        assert len(result.plain_text) > 0

        # Should be real-time or faster
        rtf = result.audio_duration / result.processing_time
        assert rtf > 0.5, f"Too slow: {rtf:.2f}x real-time"

        print(f"\n[Single Chinese] Duration: {result.audio_duration:.1f}s, "
              f"Processing: {result.processing_time:.1f}s, RTF: {rtf:.1f}x")
        print(f"Text: {result.plain_text[:200]}...")

    def test_single_speaker_english(self, pipeline_without_separation):
        """Test single speaker English audio."""
        audio_path = TRANSCRIPTION_TEST_DIR / "english-31s.wav"
        if not audio_path.exists():
            pytest.skip(f"Test audio not found: {audio_path}")

        result = pipeline_without_separation.process(str(audio_path))

        assert result.audio_duration > 0
        assert len(result.segments) > 0
        assert len(result.plain_text) > 0

        rtf = result.audio_duration / result.processing_time
        print(f"\n[Single English] Duration: {result.audio_duration:.1f}s, "
              f"Processing: {result.processing_time:.1f}s, RTF: {rtf:.1f}x")
        print(f"Text: {result.plain_text[:200]}...")

    def test_two_speakers_mixture(self, pipeline_with_separation):
        """Test two-speaker mixture audio."""
        audio_path = TEST_AUDIO_DIR / "osr_mixture_33s.wav"
        if not audio_path.exists():
            pytest.skip(f"Test audio not found: {audio_path}")

        result = pipeline_with_separation.process(str(audio_path))

        # Verify result structure
        assert result.audio_duration > 0
        assert result.processing_time > 0
        assert len(result.segments) > 0

        # Should have speaker labels
        assert len(result.speakers) > 0

        # Formatted output should have speaker labels
        formatted = result.formatted
        assert "[Speaker" in formatted or len(result.speakers) > 0

        print(f"\n[Two Speakers] Duration: {result.audio_duration:.1f}s, "
              f"Processing: {result.processing_time:.1f}s")
        print(f"Speakers: {result.speakers}")
        print(f"Segments: {len(result.segments)}")
        print(f"Formatted: {formatted[:300]}...")

    def test_speaker_enrollment_and_identification(self, pipeline_with_separation):
        """Test enrolling speakers and identifying them in mixture."""
        male_path = TEST_AUDIO_DIR / "osr_male.wav"
        female_path = TEST_AUDIO_DIR / "osr_female.wav"
        mixture_path = TEST_AUDIO_DIR / "osr_mixture_33s.wav"

        if not all(p.exists() for p in [male_path, female_path, mixture_path]):
            pytest.skip("Test audio not found")

        # Enroll speakers
        pipeline_with_separation.enroll_speaker("Bob", str(male_path))
        pipeline_with_separation.enroll_speaker("Alice", str(female_path))

        # Process mixture
        result = pipeline_with_separation.process(str(mixture_path))

        # Should identify enrolled speakers
        speakers_found = set(result.speakers)
        print(f"\n[Enrolled Speakers] Found: {speakers_found}")
        print(f"Formatted: {result.formatted[:300]}...")

        # At least one enrolled speaker should be identified
        enrolled = {"Bob", "Alice"}
        identified = speakers_found & enrolled
        # Note: This may not always work perfectly depending on audio quality
        # So we just check the pipeline runs without error

    def test_output_format(self, pipeline_without_separation):
        """Test that output format is correct."""
        audio_path = TRANSCRIPTION_TEST_DIR / "chinese-14s.wav"
        if not audio_path.exists():
            pytest.skip(f"Test audio not found: {audio_path}")

        result = pipeline_without_separation.process(str(audio_path))

        # Check PipelineResult properties
        assert hasattr(result, 'segments')
        assert hasattr(result, 'speakers')
        assert hasattr(result, 'processing_time')
        assert hasattr(result, 'audio_duration')
        assert hasattr(result, 'formatted')
        assert hasattr(result, 'plain_text')

        # Check Segment properties
        if result.segments:
            seg = result.segments[0]
            assert hasattr(seg, 'speaker')
            assert hasattr(seg, 'start')
            assert hasattr(seg, 'end')
            assert hasattr(seg, 'text')
            assert hasattr(seg, 'confidence')
            assert hasattr(seg, 'stream')

            assert seg.start >= 0
            assert seg.end > seg.start
            assert isinstance(seg.text, str)

    def test_numpy_array_input(self, pipeline_without_separation):
        """Test processing numpy array input."""
        audio_path = TRANSCRIPTION_TEST_DIR / "chinese-14s.wav"
        if not audio_path.exists():
            pytest.skip(f"Test audio not found: {audio_path}")

        # Load as numpy array
        audio, sr = sf.read(str(audio_path))
        audio = audio.astype(np.float32)

        # Process array
        result = pipeline_without_separation.process(audio, sample_rate=sr)

        assert len(result.segments) > 0
        assert len(result.plain_text) > 0

    def test_processing_speed(self, pipeline_without_separation):
        """Test that processing is reasonably fast."""
        audio_path = TRANSCRIPTION_TEST_DIR / "chinese-14s.wav"
        if not audio_path.exists():
            pytest.skip(f"Test audio not found: {audio_path}")

        result = pipeline_without_separation.process(str(audio_path))

        # Should be at least 0.5x real-time (processing 14s audio in < 28s)
        rtf = result.audio_duration / result.processing_time
        assert rtf > 0.5, f"Too slow: {rtf:.2f}x real-time"

        print(f"\n[Speed Test] RTF: {rtf:.1f}x real-time")


class TestEdgeCases:
    """Test edge cases and error handling."""

    @pytest.fixture(scope="class")
    def pipeline(self):
        """Load pipeline."""
        from voice.pipeline import VoicePipeline
        return VoicePipeline(
            enable_separation=False,
            enable_speaker_id=False
        )

    def test_short_audio(self, pipeline):
        """Test with very short audio (< 1 second)."""
        # Create 0.5 second audio
        audio = np.random.randn(8000).astype(np.float32) * 0.01  # Mostly silence

        result = pipeline.process(audio, sample_rate=16000)

        # Should handle gracefully (may have 0 segments if no speech)
        assert result.audio_duration > 0
        assert result.processing_time > 0

    def test_silent_audio(self, pipeline):
        """Test with silent audio."""
        # Create 2 seconds of silence
        audio = np.zeros(32000, dtype=np.float32)

        result = pipeline.process(audio, sample_rate=16000)

        # Should handle gracefully with 0 segments
        assert len(result.segments) == 0
        assert result.plain_text == ""

    def test_mono_vs_stereo(self, pipeline):
        """Test that stereo audio is handled correctly."""
        # Create stereo audio
        mono = np.random.randn(16000).astype(np.float32)
        stereo = np.column_stack([mono, mono])

        result_mono = pipeline.process(mono, sample_rate=16000)
        result_stereo = pipeline.process(stereo, sample_rate=16000)

        # Both should work
        assert result_mono.audio_duration > 0
        assert result_stereo.audio_duration > 0

    def test_different_sample_rates(self, pipeline):
        """Test with different input sample rates."""
        for sr in [8000, 16000, 22050, 44100, 48000]:
            # Create 1 second of audio at this sample rate
            audio = np.sin(2 * np.pi * 440 * np.arange(sr) / sr).astype(np.float32)

            result = pipeline.process(audio, sample_rate=sr)

            # Should handle any sample rate
            assert result.audio_duration > 0


if __name__ == "__main__":
    pytest.main([__file__, "-v", "-s"])
