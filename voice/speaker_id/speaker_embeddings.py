#!/usr/bin/env python3
"""
Speaker Identification module using speaker embeddings.

This module provides speaker embedding extraction and matching
using the ECAPA-TDNN model from SpeechBrain.

Usage:
    speaker_id = SpeakerID()

    # Enroll a speaker
    speaker_id.enroll("Alice", alice_audio, sample_rate=16000)

    # Identify speaker
    name, confidence = speaker_id.identify(unknown_audio, sample_rate=16000)
"""

import torch
import numpy as np
from typing import Dict, List, Tuple, Optional, Union
from pathlib import Path
import json
from dataclasses import dataclass, asdict


@dataclass
class SpeakerProfile:
    """Speaker profile with embedding and metadata."""
    name: str
    embedding: np.ndarray
    num_samples: int = 1
    created_at: str = ""

    def to_dict(self) -> dict:
        return {
            "name": self.name,
            "embedding": self.embedding.tolist(),
            "num_samples": self.num_samples,
            "created_at": self.created_at
        }

    @classmethod
    def from_dict(cls, data: dict) -> "SpeakerProfile":
        return cls(
            name=data["name"],
            embedding=np.array(data["embedding"]),
            num_samples=data.get("num_samples", 1),
            created_at=data.get("created_at", "")
        )


class SpeakerID:
    """
    Speaker identification using ECAPA-TDNN embeddings.

    The model extracts 192-dimensional speaker embeddings that can be
    compared using cosine similarity for speaker verification/identification.
    """

    def __init__(
        self,
        model_source: str = "speechbrain/spkrec-ecapa-voxceleb",
        similarity_threshold: float = 0.25,
        device: str = "cpu"
    ):
        """
        Initialize Speaker ID.

        Args:
            model_source: HuggingFace model identifier
            similarity_threshold: Minimum cosine similarity for positive match
            device: Device to run model on
        """
        self.model_source = model_source
        self.similarity_threshold = similarity_threshold
        self.device = device

        # Speaker database
        self.speakers: Dict[str, SpeakerProfile] = {}

        # Load model
        self._load_model()

    def _load_model(self):
        """Load the speaker embedding model."""
        try:
            from speechbrain.inference.speaker import EncoderClassifier

            self.model = EncoderClassifier.from_hparams(
                source=self.model_source,
                savedir=Path.home() / ".cache" / "speechbrain" / "spkrec-ecapa-voxceleb",
                run_opts={"device": self.device}
            )
            print(f"Loaded speaker embedding model: {self.model_source}")

        except ImportError:
            print("SpeechBrain not installed. Using fallback embedding method.")
            self.model = None

    def extract_embedding(
        self,
        audio: np.ndarray,
        sample_rate: int = 16000
    ) -> np.ndarray:
        """
        Extract speaker embedding from audio.

        Args:
            audio: Audio samples (mono, float32)
            sample_rate: Sample rate (16000 Hz recommended)

        Returns:
            192-dimensional speaker embedding
        """
        if self.model is None:
            # Fallback: simple MFCC-based embedding
            return self._fallback_embedding(audio, sample_rate)

        # Convert to tensor
        if isinstance(audio, np.ndarray):
            audio_tensor = torch.from_numpy(audio).float()
        else:
            audio_tensor = audio.float()

        # Ensure correct shape [batch, time]
        if audio_tensor.dim() == 1:
            audio_tensor = audio_tensor.unsqueeze(0)

        # Extract embedding
        with torch.no_grad():
            embedding = self.model.encode_batch(audio_tensor)

        return embedding.squeeze().cpu().numpy()

    def _fallback_embedding(
        self,
        audio: np.ndarray,
        sample_rate: int
    ) -> np.ndarray:
        """
        Fallback embedding using simple audio features.

        This is a simplified approach when SpeechBrain is not available.
        """
        import scipy.signal as signal

        # Resample to 16kHz if needed
        if sample_rate != 16000:
            num_samples = int(len(audio) * 16000 / sample_rate)
            audio = signal.resample(audio, num_samples)

        # Simple features: spectral statistics
        # This is a placeholder - real embeddings should use neural networks
        n_fft = 512
        hop_length = 160

        # Compute spectrogram
        f, t, Sxx = signal.spectrogram(
            audio, fs=16000, nperseg=n_fft, noverlap=n_fft - hop_length
        )

        # Extract statistics as embedding
        features = []

        # Spectral mean
        features.extend(np.mean(Sxx, axis=1)[:96])

        # Spectral std
        features.extend(np.std(Sxx, axis=1)[:96])

        embedding = np.array(features[:192])

        # Normalize
        embedding = embedding / (np.linalg.norm(embedding) + 1e-8)

        return embedding

    def enroll(
        self,
        name: str,
        audio: np.ndarray,
        sample_rate: int = 16000,
        update_existing: bool = True
    ) -> SpeakerProfile:
        """
        Enroll a new speaker or update existing profile.

        Args:
            name: Speaker name/identifier
            audio: Audio sample of the speaker
            sample_rate: Sample rate
            update_existing: If True, average with existing embedding

        Returns:
            SpeakerProfile for the enrolled speaker
        """
        from datetime import datetime

        # Extract embedding
        embedding = self.extract_embedding(audio, sample_rate)

        if name in self.speakers and update_existing:
            # Average with existing embedding
            existing = self.speakers[name]
            n = existing.num_samples
            new_embedding = (existing.embedding * n + embedding) / (n + 1)
            new_embedding = new_embedding / (np.linalg.norm(new_embedding) + 1e-8)

            profile = SpeakerProfile(
                name=name,
                embedding=new_embedding,
                num_samples=n + 1,
                created_at=existing.created_at
            )
        else:
            # Normalize embedding
            embedding = embedding / (np.linalg.norm(embedding) + 1e-8)

            profile = SpeakerProfile(
                name=name,
                embedding=embedding,
                num_samples=1,
                created_at=datetime.now().isoformat()
            )

        self.speakers[name] = profile
        return profile

    def identify(
        self,
        audio: np.ndarray,
        sample_rate: int = 16000
    ) -> Tuple[Optional[str], float]:
        """
        Identify speaker from audio.

        Args:
            audio: Audio sample
            sample_rate: Sample rate

        Returns:
            Tuple of (speaker_name, confidence)
            Returns (None, 0.0) if no match above threshold
        """
        if not self.speakers:
            return None, 0.0

        # Extract embedding
        embedding = self.extract_embedding(audio, sample_rate)
        embedding = embedding / (np.linalg.norm(embedding) + 1e-8)

        # Find best match
        best_name = None
        best_similarity = -1.0

        for name, profile in self.speakers.items():
            similarity = self._cosine_similarity(embedding, profile.embedding)
            if similarity > best_similarity:
                best_similarity = similarity
                best_name = name

        if best_similarity >= self.similarity_threshold:
            return best_name, best_similarity
        else:
            return None, best_similarity

    def verify(
        self,
        audio: np.ndarray,
        claimed_name: str,
        sample_rate: int = 16000
    ) -> Tuple[bool, float]:
        """
        Verify if audio matches claimed speaker.

        Args:
            audio: Audio sample
            claimed_name: Name of claimed speaker
            sample_rate: Sample rate

        Returns:
            Tuple of (is_match, similarity_score)
        """
        if claimed_name not in self.speakers:
            return False, 0.0

        # Extract embedding
        embedding = self.extract_embedding(audio, sample_rate)
        embedding = embedding / (np.linalg.norm(embedding) + 1e-8)

        # Compare with claimed speaker
        profile = self.speakers[claimed_name]
        similarity = self._cosine_similarity(embedding, profile.embedding)

        is_match = similarity >= self.similarity_threshold
        return is_match, similarity

    def _cosine_similarity(self, a: np.ndarray, b: np.ndarray) -> float:
        """Compute cosine similarity between two vectors."""
        return float(np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b) + 1e-8))

    def save_profiles(self, path: Union[str, Path]):
        """Save speaker profiles to file."""
        path = Path(path)
        data = {
            name: profile.to_dict()
            for name, profile in self.speakers.items()
        }
        with open(path, 'w') as f:
            json.dump(data, f, indent=2)
        print(f"Saved {len(self.speakers)} speaker profiles to {path}")

    def load_profiles(self, path: Union[str, Path]):
        """Load speaker profiles from file."""
        path = Path(path)
        if not path.exists():
            print(f"No profiles file at {path}")
            return

        with open(path, 'r') as f:
            data = json.load(f)

        self.speakers = {
            name: SpeakerProfile.from_dict(profile_data)
            for name, profile_data in data.items()
        }
        print(f"Loaded {len(self.speakers)} speaker profiles from {path}")

    def list_speakers(self) -> List[str]:
        """List all enrolled speakers."""
        return list(self.speakers.keys())

    def remove_speaker(self, name: str) -> bool:
        """Remove a speaker from the database."""
        if name in self.speakers:
            del self.speakers[name]
            return True
        return False


def test_speaker_id():
    """Test speaker ID with synthetic audio."""
    print("Testing Speaker ID...")

    # Create Speaker ID (will use fallback if SpeechBrain not installed)
    speaker_id = SpeakerID()

    sample_rate = 16000
    duration = 3.0
    t = np.linspace(0, duration, int(duration * sample_rate))

    # Create different "speakers" with different frequency profiles
    # Speaker 1: lower frequencies
    speaker1_audio = np.zeros_like(t, dtype=np.float32)
    for freq in [150, 200, 250, 300]:
        speaker1_audio += 0.1 * np.sin(2 * np.pi * freq * t)

    # Speaker 2: higher frequencies
    speaker2_audio = np.zeros_like(t, dtype=np.float32)
    for freq in [300, 400, 500, 600]:
        speaker2_audio += 0.1 * np.sin(2 * np.pi * freq * t)

    # Normalize
    speaker1_audio = speaker1_audio / np.abs(speaker1_audio).max() * 0.5
    speaker2_audio = speaker2_audio / np.abs(speaker2_audio).max() * 0.5

    # Enroll speakers
    print("  Enrolling speakers...")
    speaker_id.enroll("Speaker1", speaker1_audio, sample_rate)
    speaker_id.enroll("Speaker2", speaker2_audio, sample_rate)
    print(f"  Enrolled: {speaker_id.list_speakers()}")

    # Test identification
    print("  Testing identification...")
    name1, conf1 = speaker_id.identify(speaker1_audio, sample_rate)
    print(f"    Speaker1 audio -> {name1} (confidence: {conf1:.3f})")

    name2, conf2 = speaker_id.identify(speaker2_audio, sample_rate)
    print(f"    Speaker2 audio -> {name2} (confidence: {conf2:.3f})")

    # Test verification
    print("  Testing verification...")
    is_match, sim = speaker_id.verify(speaker1_audio, "Speaker1", sample_rate)
    print(f"    Speaker1 audio vs 'Speaker1': match={is_match}, similarity={sim:.3f}")

    is_match, sim = speaker_id.verify(speaker1_audio, "Speaker2", sample_rate)
    print(f"    Speaker1 audio vs 'Speaker2': match={is_match}, similarity={sim:.3f}")

    print("  Speaker ID test complete!")
    return True


if __name__ == "__main__":
    test_speaker_id()
