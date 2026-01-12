#!/usr/bin/env python3
"""
Voice Pipeline - Unified speech processing with speaker separation and identification.

Connects all voice components:
1. Speech Separation (SepReformer) - 8kHz
2. VAD (Silero) - 16kHz
3. Speaker ID (ECAPA-TDNN) - 16kHz
4. Transcription (SenseVoice CoreML) - 16kHz

Usage:
    from voice.pipeline import VoicePipeline

    pipeline = VoicePipeline()
    result = pipeline.process("conversation.wav")
    print(result.formatted)  # "[Speaker 1] Hello [Speaker 2] Hi there"
"""

import numpy as np
import soundfile as sf
import torchaudio.functional as F
import torch
import coremltools as ct
from dataclasses import dataclass, field
from typing import List, Tuple, Optional, Union
from pathlib import Path
import time


@dataclass
class Segment:
    """A single speech segment with speaker and transcript."""
    speaker: str           # "Speaker 1", "Speaker 2", or enrolled name
    start: float          # Start time in seconds
    end: float            # End time in seconds
    text: str             # Transcribed text
    confidence: float     # Speaker ID confidence (0-1)
    stream: int = 0       # Which separated stream (0 or 1)


@dataclass
class PipelineResult:
    """Result from processing audio through the pipeline."""
    segments: List[Segment] = field(default_factory=list)
    speakers: List[str] = field(default_factory=list)
    processing_time: float = 0.0
    audio_duration: float = 0.0

    @property
    def formatted(self) -> str:
        """Format segments as labeled transcript."""
        if not self.segments:
            return ""

        # Sort by start time
        sorted_segments = sorted(self.segments, key=lambda s: s.start)

        parts = []
        for seg in sorted_segments:
            if seg.text.strip():
                parts.append(f"[{seg.speaker}] {seg.text.strip()}")

        return " ".join(parts)

    @property
    def plain_text(self) -> str:
        """Get plain text without speaker labels."""
        sorted_segments = sorted(self.segments, key=lambda s: s.start)
        return " ".join(seg.text.strip() for seg in sorted_segments if seg.text.strip())


class VoicePipeline:
    """
    Unified voice processing pipeline.

    Pipeline stages:
    1. Resample input to 8kHz for separation
    2. Separate speakers (SepReformer)
    3. Resample separated streams to 16kHz
    4. VAD on each stream
    5. Speaker ID on each segment
    6. Transcribe each segment
    7. Merge and format output
    """

    SAMPLE_RATE_SEPARATION = 8000   # SepReformer uses 8kHz
    SAMPLE_RATE_PROCESSING = 16000  # VAD, Speaker ID, Transcription use 16kHz
    SEPARATION_CHUNK_SIZE = 32000   # 4 seconds at 8kHz

    def __init__(
        self,
        enable_separation: bool = True,
        enable_speaker_id: bool = True,
        transcription_frames: int = 500,
        transcription_itn: bool = True,
        separation_model_path: Optional[str] = None,
    ):
        """
        Initialize the voice pipeline.

        Args:
            enable_separation: Whether to separate speakers (disable for single-speaker audio)
            enable_speaker_id: Whether to identify speakers
            transcription_frames: Frame count for transcription model (250 or 500)
            transcription_itn: Enable punctuation in transcription
            separation_model_path: Path to SepReformer CoreML model
        """
        self.enable_separation = enable_separation
        self.enable_speaker_id = enable_speaker_id

        print("Initializing Voice Pipeline...")
        start = time.time()

        # Load separation model (CoreML)
        if enable_separation:
            if separation_model_path is None:
                separation_model_path = Path(__file__).parent / "separation" / "models" / "SepReformer_Base.mlpackage"
            print(f"  Loading separation model...")
            self.separator = ct.models.MLModel(str(separation_model_path))
        else:
            self.separator = None

        # Load VAD
        print(f"  Loading VAD...")
        from voice.vad import SileroVAD
        self.vad = SileroVAD()

        # Load Speaker ID
        if enable_speaker_id:
            print(f"  Loading speaker ID...")
            from voice.speaker_id import SpeakerID
            self.speaker_id = SpeakerID()
        else:
            self.speaker_id = None

        # Load transcription
        print(f"  Loading transcription model...")
        from voice.transcription.sensevoice_coreml import SenseVoiceCoreML
        self.transcriber = SenseVoiceCoreML(
            frames=transcription_frames,
            itn=transcription_itn
        )

        print(f"  Pipeline ready in {time.time() - start:.1f}s")

    def _resample(self, audio: np.ndarray, orig_sr: int, target_sr: int) -> np.ndarray:
        """Resample audio using torchaudio."""
        if orig_sr == target_sr:
            return audio
        audio_tensor = torch.from_numpy(audio).float()
        resampled = F.resample(audio_tensor, orig_sr, target_sr)
        return resampled.numpy()

    def _separate_speakers(self, audio: np.ndarray) -> Tuple[np.ndarray, np.ndarray]:
        """
        Separate audio into two speaker streams.

        Args:
            audio: Audio at 8kHz

        Returns:
            (speaker1_audio, speaker2_audio) both at 8kHz
        """
        # Pad to multiple of chunk size
        chunk_size = self.SEPARATION_CHUNK_SIZE
        pad_len = (chunk_size - len(audio) % chunk_size) % chunk_size
        if pad_len > 0:
            audio = np.pad(audio, (0, pad_len))

        num_chunks = len(audio) // chunk_size
        speaker1_chunks = []
        speaker2_chunks = []

        for i in range(num_chunks):
            chunk = audio[i * chunk_size:(i + 1) * chunk_size]
            chunk_input = chunk.astype(np.float32).reshape(1, -1)

            output = self.separator.predict({"audio_input": chunk_input})
            speaker1_chunks.append(output["speaker1"].flatten())
            speaker2_chunks.append(output["speaker2"].flatten())

        speaker1 = np.concatenate(speaker1_chunks)
        speaker2 = np.concatenate(speaker2_chunks)

        # Remove padding
        if pad_len > 0:
            original_len = len(audio) - pad_len
            speaker1 = speaker1[:original_len]
            speaker2 = speaker2[:original_len]

        return speaker1, speaker2

    def _process_stream(
        self,
        audio: np.ndarray,
        stream_id: int,
        default_speaker: str
    ) -> List[Segment]:
        """
        Process a single audio stream (VAD → Speaker ID → Transcription).

        Args:
            audio: Audio at 16kHz
            stream_id: Stream identifier (0 or 1)
            default_speaker: Default speaker name if ID not available

        Returns:
            List of Segment objects
        """
        segments = []

        # Run VAD to detect speech segments
        speech_segments = self.vad.detect_speech(audio, sample_rate=self.SAMPLE_RATE_PROCESSING)

        if not speech_segments:
            return segments

        for start_time, end_time in speech_segments:
            # Extract segment audio
            start_sample = int(start_time * self.SAMPLE_RATE_PROCESSING)
            end_sample = int(end_time * self.SAMPLE_RATE_PROCESSING)
            segment_audio = audio[start_sample:end_sample]

            # Skip very short segments
            if len(segment_audio) < self.SAMPLE_RATE_PROCESSING * 0.3:  # < 300ms
                continue

            # Speaker identification
            speaker = default_speaker
            confidence = 0.0
            if self.speaker_id is not None:
                identified, conf = self.speaker_id.identify(
                    segment_audio,
                    sample_rate=self.SAMPLE_RATE_PROCESSING
                )
                confidence = conf
                if identified:
                    speaker = identified

            # Transcription
            text, _ = self.transcriber.transcribe_audio(segment_audio)

            segments.append(Segment(
                speaker=speaker,
                start=start_time,
                end=end_time,
                text=text,
                confidence=confidence,
                stream=stream_id
            ))

        return segments

    def process(
        self,
        audio_input: Union[str, Path, np.ndarray],
        sample_rate: int = None
    ) -> PipelineResult:
        """
        Process audio through the full pipeline.

        Args:
            audio_input: Path to audio file, or numpy array
            sample_rate: Sample rate (required if audio_input is array)

        Returns:
            PipelineResult with segments, speakers, and formatted transcript
        """
        start_time = time.time()

        # Load audio
        if isinstance(audio_input, (str, Path)):
            audio, sr = sf.read(str(audio_input))
            audio = audio.astype(np.float32)
        else:
            audio = audio_input.astype(np.float32)
            sr = sample_rate
            if sr is None:
                raise ValueError("sample_rate required when passing audio array")

        # Convert to mono if stereo
        if len(audio.shape) > 1:
            audio = audio.mean(axis=1)

        audio_duration = len(audio) / sr

        all_segments = []
        speakers = set()

        if self.enable_separation and self.separator is not None:
            # === SEPARATION PIPELINE ===

            # 1. Resample to 8kHz for separation
            audio_8k = self._resample(audio, sr, self.SAMPLE_RATE_SEPARATION)

            # 2. Separate speakers
            speaker1_8k, speaker2_8k = self._separate_speakers(audio_8k)

            # 3. Resample back to 16kHz
            speaker1_16k = self._resample(speaker1_8k, self.SAMPLE_RATE_SEPARATION, self.SAMPLE_RATE_PROCESSING)
            speaker2_16k = self._resample(speaker2_8k, self.SAMPLE_RATE_SEPARATION, self.SAMPLE_RATE_PROCESSING)

            # 4. Process each stream
            segments1 = self._process_stream(speaker1_16k, stream_id=0, default_speaker="Speaker 1")
            segments2 = self._process_stream(speaker2_16k, stream_id=1, default_speaker="Speaker 2")

            all_segments.extend(segments1)
            all_segments.extend(segments2)

        else:
            # === SINGLE SPEAKER PIPELINE ===

            # Resample to 16kHz
            audio_16k = self._resample(audio, sr, self.SAMPLE_RATE_PROCESSING)

            # Process as single stream
            segments = self._process_stream(audio_16k, stream_id=0, default_speaker="Speaker")
            all_segments.extend(segments)

        # Collect unique speakers
        for seg in all_segments:
            speakers.add(seg.speaker)

        processing_time = time.time() - start_time

        return PipelineResult(
            segments=all_segments,
            speakers=sorted(list(speakers)),
            processing_time=processing_time,
            audio_duration=audio_duration
        )

    def enroll_speaker(self, name: str, audio_input: Union[str, Path, np.ndarray], sample_rate: int = None):
        """
        Enroll a speaker for identification.

        Args:
            name: Speaker name
            audio_input: Path to audio file, or numpy array
            sample_rate: Sample rate (required if audio_input is array)
        """
        if self.speaker_id is None:
            raise RuntimeError("Speaker ID not enabled")

        # Load audio
        if isinstance(audio_input, (str, Path)):
            audio, sr = sf.read(str(audio_input))
            audio = audio.astype(np.float32)
        else:
            audio = audio_input.astype(np.float32)
            sr = sample_rate
            if sr is None:
                raise ValueError("sample_rate required when passing audio array")

        # Resample to 16kHz if needed
        if sr != self.SAMPLE_RATE_PROCESSING:
            audio = self._resample(audio, sr, self.SAMPLE_RATE_PROCESSING)

        self.speaker_id.enroll(name, audio, sample_rate=self.SAMPLE_RATE_PROCESSING)
        print(f"Enrolled speaker: {name}")


def test_pipeline():
    """Test the voice pipeline with sample audio."""
    print("=" * 60)
    print("Voice Pipeline Test")
    print("=" * 60)

    # Initialize pipeline
    pipeline = VoicePipeline(
        enable_separation=True,
        enable_speaker_id=True
    )

    # Test with 2-speaker mixture
    test_file = Path(__file__).parent / "separation" / "test_audio" / "osr_mixture_33s.wav"

    if test_file.exists():
        print(f"\nProcessing: {test_file}")
        result = pipeline.process(str(test_file))

        print(f"\nResults:")
        print(f"  Duration: {result.audio_duration:.1f}s")
        print(f"  Processing time: {result.processing_time:.1f}s")
        print(f"  Real-time factor: {result.audio_duration / result.processing_time:.1f}x")
        print(f"  Speakers: {result.speakers}")
        print(f"  Segments: {len(result.segments)}")
        print(f"\nFormatted output:")
        print(result.formatted[:500] + "..." if len(result.formatted) > 500 else result.formatted)
    else:
        print(f"Test file not found: {test_file}")


if __name__ == "__main__":
    test_pipeline()
