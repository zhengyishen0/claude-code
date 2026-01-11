#!/usr/bin/env python3
"""
Live Voice Pipeline - VAD-Driven Streaming

Press Option to START recording
Press Option to STOP recording

During recording:
  - VAD detects speech segments in real-time
  - Each segment is processed immediately (embedding + transcription in parallel)
  - LIVE output: [Speaker A] (1.2s-3.5s) Hello how are you

After stop:
  - Speed breakdown
  - Clustering summary (groups unknown speakers)
  - Option to name speakers
"""

# Suppress warnings before any imports
import warnings
warnings.filterwarnings('ignore', message='.*scikit-learn.*')
warnings.filterwarnings('ignore', message='.*Torch version.*')
warnings.filterwarnings('ignore', message='.*urllib3.*')
warnings.filterwarnings('ignore', message='.*torchaudio.*')

import sys
from pathlib import Path as _Path
_VOICE_DIR = _Path(__file__).parent
sys.path.insert(0, str(_VOICE_DIR))
sys.path.insert(0, str(_VOICE_DIR / 'transcription'))

import time
import threading
import queue
import json
import numpy as np
import torch
import sounddevice as sd
import soundfile as sf
from pathlib import Path
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor
from sklearn.cluster import AgglomerativeClustering
from pynput import keyboard

VOICE_DIR = Path(__file__).parent
LIBRARY_PATH = VOICE_DIR / "speaker_id" / "voice_library.json"
RECORDINGS_DIR = VOICE_DIR / "recordings"
SAMPLE_RATE = 16000
CHUNK_SIZE = 512  # ~32ms at 16kHz


def is_valid_transcript(text: str) -> bool:
    """Filter out empty/punctuation-only transcripts."""
    if not text:
        return False
    # Remove all punctuation and whitespace
    cleaned = ''.join(c for c in text if c.isalnum())
    return len(cleaned) > 0


def cosine_similarity(a, b):
    """Compute cosine similarity between two vectors."""
    a_norm = a / np.linalg.norm(a)
    b_norm = b / np.linalg.norm(b)
    return np.dot(a_norm, b_norm)


def cosine_distance(a, b):
    """Compute cosine distance (1 - similarity)."""
    return 1.0 - cosine_similarity(a, b)


class SpeakerProfile:
    """
    Two-layer speaker profile with core and boundary embeddings.

    Core: Frequent voice patterns (within 1σ of centroid)
    Boundary: Edge case voice patterns (1σ to 2σ from centroid)

    Uses distance from centroid as proxy for frequency.
    """

    # Limits to prevent unbounded growth
    MAX_CORE = 5
    MAX_BOUNDARY = 10
    MIN_DIVERSITY = 0.1  # Minimum distance to add new embedding

    def __init__(self, name: str, initial_embedding: np.ndarray = None):
        self.name = name
        self.core = []  # High-frequency embeddings (close to centroid)
        self.boundary = []  # Edge-case embeddings (far from centroid)
        self.centroid = None
        self.std_dev = 0.2  # Default until we have enough data
        self.all_distances = []  # Track distances to compute σ

        if initial_embedding is not None:
            self.core.append(initial_embedding)
            self.centroid = initial_embedding.copy()

    def _update_centroid(self):
        """Recompute centroid from core embeddings."""
        if self.core:
            self.centroid = np.mean(self.core, axis=0)

    def _update_std_dev(self):
        """Recompute standard deviation from distance history."""
        if len(self.all_distances) >= 3:
            self.std_dev = max(np.std(self.all_distances), 0.05)  # Min 0.05

    def _is_diverse_from(self, embedding: np.ndarray, existing: list, min_dist: float) -> bool:
        """Check if embedding is diverse enough from existing ones."""
        if not existing:
            return True
        distances = [cosine_distance(embedding, e) for e in existing]
        return min(distances) >= min_dist

    def add_embedding(self, embedding: np.ndarray, force_boundary: bool = False) -> str:
        """
        Add embedding to appropriate layer based on distance from centroid.

        Args:
            embedding: Voice embedding vector
            force_boundary: If True, add to boundary regardless of distance
                           (used for user-confirmed outliers)

        Returns: "core", "boundary", or "rejected"
        """
        if self.centroid is None:
            self.core.append(embedding)
            self.centroid = embedding.copy()
            return "core"

        dist = cosine_distance(embedding, self.centroid)
        self.all_distances.append(dist)
        self._update_std_dev()

        # Force-add to boundary (for user-confirmed outliers)
        if force_boundary:
            if len(self.boundary) < self.MAX_BOUNDARY:
                if self._is_diverse_from(embedding, self.boundary, self.MIN_DIVERSITY):
                    self.boundary.append(embedding)
                    return "boundary"
            return "rejected"  # Boundary full or not diverse enough

        # Classify by distance (using σ thresholds)
        if dist < 1.0 * self.std_dev:
            # Within 1σ → Core candidate
            if len(self.core) < self.MAX_CORE:
                if self._is_diverse_from(embedding, self.core, self.MIN_DIVERSITY):
                    self.core.append(embedding)
                    self._update_centroid()
                    return "core"
            return "rejected"  # Core full or not diverse enough

        elif dist < 2.0 * self.std_dev:
            # Between 1σ and 2σ → Boundary candidate
            if len(self.boundary) < self.MAX_BOUNDARY:
                if self._is_diverse_from(embedding, self.boundary, self.MIN_DIVERSITY):
                    self.boundary.append(embedding)
                    return "boundary"
            return "rejected"  # Boundary full or not diverse enough

        else:
            # Beyond 2σ → Too far, might be noise
            return "rejected"

    def max_similarity_to_core(self, embedding: np.ndarray) -> float:
        """Get max similarity to any core embedding."""
        if not self.core:
            return 0.0
        return max(cosine_similarity(embedding, e) for e in self.core)

    def max_similarity_to_boundary(self, embedding: np.ndarray) -> float:
        """Get max similarity to any boundary embedding."""
        all_embs = self.core + self.boundary
        if not all_embs:
            return 0.0
        return max(cosine_similarity(embedding, e) for e in all_embs)

    def to_dict(self) -> dict:
        """Serialize to dict for JSON storage."""
        return {
            "core": [e.tolist() for e in self.core],
            "boundary": [e.tolist() for e in self.boundary],
            "centroid": self.centroid.tolist() if self.centroid is not None else None,
            "std_dev": self.std_dev,
            "all_distances": self.all_distances[-100:]  # Keep last 100
        }

    @classmethod
    def from_dict(cls, name: str, data: dict) -> "SpeakerProfile":
        """Deserialize from dict."""
        profile = cls(name)
        profile.core = [np.array(e) for e in data.get("core", [])]
        profile.boundary = [np.array(e) for e in data.get("boundary", [])]
        if data.get("centroid"):
            profile.centroid = np.array(data["centroid"])
        profile.std_dev = data.get("std_dev", 0.2)
        profile.all_distances = data.get("all_distances", [])
        return profile

    @classmethod
    def from_legacy(cls, name: str, embeddings: list) -> "SpeakerProfile":
        """Convert from old format (list of embeddings) to new format."""
        profile = cls(name)
        if embeddings:
            # First embedding becomes centroid
            profile.centroid = np.array(embeddings[0])
            # Add all embeddings (will be classified into layers)
            for emb in embeddings:
                emb_array = np.array(emb) if not isinstance(emb, np.ndarray) else emb
                profile.add_embedding(emb_array)
        return profile


class VoiceLibrary:
    """
    Persistent voice library with two-layer speaker profiles.

    Features:
    - Core/boundary layers for each speaker
    - Two-phase matching (boundary first, core for conflicts)
    - Self-improvement: auto-learns from high-confidence matches
    """

    BOUNDARY_THRESHOLD = 0.35  # Min score to match boundary
    CORE_THRESHOLD = 0.45  # Min score to match core
    AUTO_LEARN_THRESHOLD = 0.55  # Min score for auto-learning
    CONFLICT_MARGIN = 0.1  # Score gap to resolve conflicts

    def __init__(self, path=LIBRARY_PATH):
        self.path = path
        self.speakers: dict[str, SpeakerProfile] = {}
        self.load()

    def load(self):
        if self.path.exists():
            with open(self.path) as f:
                data = json.load(f)

            for name, value in data.items():
                if isinstance(value, dict) and "core" in value:
                    # New format with layers
                    self.speakers[name] = SpeakerProfile.from_dict(name, value)
                else:
                    # Legacy format (list of embeddings)
                    self.speakers[name] = SpeakerProfile.from_legacy(name, value)

            print(f"  📂 Loaded {len(self.speakers)} speakers: {list(self.speakers.keys())}")

    def save(self):
        data = {name: profile.to_dict() for name, profile in self.speakers.items()}
        with open(self.path, 'w') as f:
            json.dump(data, f, indent=2)

    def add_speaker(self, name: str, embedding: np.ndarray):
        """Add a new speaker with initial embedding."""
        if name not in self.speakers:
            self.speakers[name] = SpeakerProfile(name, embedding)
            self.save()
            return True
        return False

    def add_embedding(self, name: str, embedding: np.ndarray, force_boundary: bool = False) -> str:
        """Add embedding to existing speaker's profile."""
        if name not in self.speakers:
            self.speakers[name] = SpeakerProfile(name, embedding)
            self.save()
            return "core"

        result = self.speakers[name].add_embedding(embedding, force_boundary=force_boundary)
        if result != "rejected":
            self.save()
        return result

    def match(self, embedding: np.ndarray, threshold: float = None) -> tuple:
        """
        Two-phase matching: boundary first, then core if conflict.

        Returns: (name, score, confidence)
            - name: Speaker name or None
            - score: Best match score
            - confidence: "high", "medium", "low", or "conflict"
        """
        if not self.speakers:
            return None, 0.0, "low"

        threshold = threshold or self.BOUNDARY_THRESHOLD

        # Phase 1: Check all boundary layers
        boundary_matches = []
        for name, profile in self.speakers.items():
            score = profile.max_similarity_to_boundary(embedding)
            if score >= threshold:
                boundary_matches.append((name, score, profile))

        if len(boundary_matches) == 0:
            return None, 0.0, "low"

        if len(boundary_matches) == 1:
            name, score, profile = boundary_matches[0]
            confidence = "high" if score >= self.AUTO_LEARN_THRESHOLD else "medium"
            return name, score, confidence

        # Phase 2: Conflict - use core scores to distinguish
        core_scores = []
        for name, _, profile in boundary_matches:
            core_score = profile.max_similarity_to_core(embedding)
            core_scores.append((name, core_score, profile))

        core_scores.sort(key=lambda x: x[1], reverse=True)
        best_name, best_score, best_profile = core_scores[0]
        second_name, second_score, _ = core_scores[1]

        if best_score - second_score >= self.CONFLICT_MARGIN:
            # Core distinguishes them
            confidence = "high" if best_score >= self.AUTO_LEARN_THRESHOLD else "medium"
            return best_name, best_score, confidence
        else:
            # Still ambiguous
            return f"[{best_name}/{second_name}?]", best_score, "conflict"

    def auto_learn(self, name: str, embedding: np.ndarray, score: float) -> bool:
        """
        Auto-learn from high-confidence match.

        Returns True if embedding was added.
        """
        if score >= self.AUTO_LEARN_THRESHOLD and name in self.speakers:
            result = self.speakers[name].add_embedding(embedding)
            if result != "rejected":
                self.save()
                return True
        return False


class VADProcessor:
    """VAD-driven audio processor with streaming output."""

    def __init__(self, vad_model, vad_utils):
        self.vad_model = vad_model
        self.get_speech_timestamps = vad_utils[0]

        # VAD state
        self.audio_buffer = []
        self.speech_buffer = []
        self.is_speech = False
        self.speech_start_sample = 0
        self.total_samples = 0

        # Thresholds
        self.speech_threshold = 0.5
        self.min_speech_duration = 0.3  # seconds
        self.min_silence_duration = 0.3  # seconds
        self.silence_samples = 0

    def reset(self):
        self.audio_buffer = []
        self.speech_buffer = []
        self.is_speech = False
        self.speech_start_sample = 0
        self.total_samples = 0
        self.silence_samples = 0

    def process_chunk(self, audio_chunk):
        """
        Process audio chunk through VAD.
        Returns (segment_audio, start_time, end_time) when speech ends, else None.
        """
        self.audio_buffer.extend(audio_chunk)
        self.total_samples += len(audio_chunk)

        # Need enough samples for VAD (at least 512)
        if len(audio_chunk) < 512:
            return None

        # Get VAD probability
        audio_tensor = torch.from_numpy(np.array(audio_chunk, dtype=np.float32))
        speech_prob = self.vad_model(audio_tensor, SAMPLE_RATE).item()

        if speech_prob >= self.speech_threshold:
            self.silence_samples = 0
            if not self.is_speech:
                # Speech started
                self.is_speech = True
                self.speech_start_sample = self.total_samples - len(audio_chunk)
                self.speech_buffer = list(audio_chunk)
            else:
                # Speech continues
                self.speech_buffer.extend(audio_chunk)
        else:
            if self.is_speech:
                self.silence_samples += len(audio_chunk)
                self.speech_buffer.extend(audio_chunk)

                # Check if silence is long enough to end speech
                if self.silence_samples >= int(self.min_silence_duration * SAMPLE_RATE):
                    # Speech ended
                    self.is_speech = False

                    # Check minimum duration
                    speech_duration = len(self.speech_buffer) / SAMPLE_RATE
                    if speech_duration >= self.min_speech_duration:
                        segment = np.array(self.speech_buffer, dtype=np.float32)
                        start_time = self.speech_start_sample / SAMPLE_RATE
                        end_time = (self.speech_start_sample + len(self.speech_buffer)) / SAMPLE_RATE

                        self.speech_buffer = []
                        self.silence_samples = 0
                        return segment, start_time, end_time

                    self.speech_buffer = []
                    self.silence_samples = 0

        return None


class LivePipeline:
    """Live voice processing pipeline with real-time streaming output."""

    def __init__(self):
        self.library = None
        self.vad_model = None
        self.vad_utils = None
        self.vad_processor = None
        self.speaker_model = None
        self.asr_model = None
        self.executor = ThreadPoolExecutor(max_workers=4)

        # State
        self.is_recording = False
        self.segments = []
        self.recording_start_time = None
        self.raw_audio = []  # Store raw audio for saving
        self.last_recording_path = None

        # Threading
        self.audio_queue = queue.Queue()
        self.stop_event = threading.Event()
        self.process_thread = None

    def load_models(self):
        print("\n📦 Loading models...")
        t_total = time.time()

        self.library = VoiceLibrary()

        t0 = time.time()
        self.vad_model, self.vad_utils = torch.hub.load(
            'snakers4/silero-vad', 'silero_vad',
            force_reload=False, onnx=False
        )
        print(f"  VAD: {time.time()-t0:.2f}s")

        t0 = time.time()
        from speechbrain.inference.speaker import EncoderClassifier
        self.speaker_model = EncoderClassifier.from_hparams(
            source='speechbrain/spkrec-ecapa-voxceleb',
            savedir='pretrained_models/spkrec-ecapa-voxceleb'
        )
        print(f"  Speaker: {time.time()-t0:.2f}s")

        t0 = time.time()
        from sensevoice_coreml import SenseVoiceCoreML
        self.asr_model = SenseVoiceCoreML(frames=500, compiled=True, itn=True)
        print(f"  ASR: {time.time()-t0:.2f}s")

        # Initialize VAD processor
        self.vad_processor = VADProcessor(self.vad_model, self.vad_utils)

        print(f"  Total: {time.time()-t_total:.2f}s")

    def extract_embedding(self, audio):
        audio_t = torch.from_numpy(audio).float().unsqueeze(0)
        emb = self.speaker_model.encode_batch(audio_t)
        return emb.squeeze().numpy()

    def process_segment(self, audio, start_time, end_time):
        """Process segment with parallel embedding + transcription + speaker matching."""
        timings = {}

        def do_embedding_and_match():
            """Run embedding AND matching together (both speaker-related)."""
            t = time.time()
            emb = self.extract_embedding(audio)
            emb_time = (time.time() - t) * 1000

            t = time.time()
            name, score, confidence = self.library.match(emb)
            match_time = (time.time() - t) * 1000

            return emb, name, score, confidence, emb_time, match_time

        def do_transcription():
            t = time.time()
            text, _ = self.asr_model.transcribe_audio(audio)
            return text.strip(), (time.time() - t) * 1000

        # Run in parallel: (embedding + matching) || transcription
        speaker_future = self.executor.submit(do_embedding_and_match)
        trans_future = self.executor.submit(do_transcription)

        embedding, name, score, confidence, emb_time, match_time = speaker_future.result()
        text, trans_time = trans_future.result()

        timings['embedding'] = emb_time
        timings['match'] = match_time
        timings['transcribe'] = trans_time

        # Filter invalid transcripts
        if not is_valid_transcript(text):
            return None

        # Determine speaker status
        is_known = name is not None and not name.startswith("[")
        is_conflict = confidence == "conflict"

        # Note: We DON'T auto-learn from high-confidence matches anymore.
        # High-confidence = already well-represented, learning adds no value.
        # Medium-confidence = edge cases that expand the boundary (valuable).
        # We learn from medium-confidence after user confirmation in auto_learn_and_confirm_outliers().
        learned = False

        # Store segment
        segment = {
            'start': start_time,
            'end': end_time,
            'text': text,
            'embedding': embedding,
            'speaker_name': name,
            'match_score': score,
            'confidence': confidence,
            'is_known': is_known,
            'is_conflict': is_conflict,
            'learned': learned,
            'timings': timings,
            'duration': end_time - start_time
        }
        self.segments.append(segment)

        # LIVE OUTPUT with confidence indicator
        if is_known:
            if confidence == "high":
                speaker_label = f"{name}"
                learn_indicator = " 📚" if learned else ""
            else:
                speaker_label = f"{name}?"
                learn_indicator = ""
        elif is_conflict:
            speaker_label = name  # Already formatted as [A/B?]
            learn_indicator = ""
        else:
            speaker_label = "???"
            learn_indicator = ""

        total_time = sum(timings.values())
        print(f"[{speaker_label}] ({start_time:.1f}s-{end_time:.1f}s) {text}  [{total_time:.0f}ms]{learn_indicator}")

        return segment

    def audio_callback(self, indata, frames, time_info, status):
        """Called by sounddevice for each audio chunk."""
        if status:
            print(f"Audio status: {status}")
        if self.is_recording:
            audio_chunk = indata[:, 0].copy()
            self.audio_queue.put(audio_chunk)
            self.raw_audio.append(audio_chunk)  # Store for saving

    def processing_loop(self):
        """Background thread: VAD + process segments."""
        while not self.stop_event.is_set() or not self.audio_queue.empty():
            try:
                audio_chunk = self.audio_queue.get(timeout=0.1)
            except queue.Empty:
                continue

            # Process through VAD
            result = self.vad_processor.process_chunk(audio_chunk)

            if result is not None:
                segment_audio, start_time, end_time = result
                # Process segment (this will print live output)
                self.process_segment(segment_audio, start_time, end_time)

    def start_recording(self):
        self.is_recording = True
        self.segments = []
        self.raw_audio = []  # Reset raw audio buffer
        self.recording_start_time = time.time()
        self.stop_event.clear()
        self.vad_processor.reset()

        # Clear audio queue
        while not self.audio_queue.empty():
            try:
                self.audio_queue.get_nowait()
            except queue.Empty:
                break

        # Start processing thread
        self.process_thread = threading.Thread(target=self.processing_loop, daemon=True)
        self.process_thread.start()

        # Start audio stream
        self.stream = sd.InputStream(
            samplerate=SAMPLE_RATE,
            channels=1,
            blocksize=CHUNK_SIZE,
            callback=self.audio_callback
        )
        self.stream.start()

        print("\n🎤 Recording... (press Option to stop)\n")
        print("-" * 60)

    def stop_recording(self):
        self.is_recording = False
        recording_duration = time.time() - self.recording_start_time

        # Stop audio stream
        if hasattr(self, 'stream'):
            self.stream.stop()
            self.stream.close()

        # Signal processing thread to stop and wait
        self.stop_event.set()
        if self.process_thread:
            self.process_thread.join(timeout=2.0)

        print("-" * 60)
        print(f"\n⏹️  Stopped. Recorded {recording_duration:.1f}s")

        # Save recording to file
        if self.raw_audio:
            self.save_recording()

        return recording_duration

    def save_recording(self):
        """Save the raw audio to a timestamped WAV file."""
        RECORDINGS_DIR.mkdir(exist_ok=True)

        # Create timestamped filename
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"recording_{timestamp}.wav"
        filepath = RECORDINGS_DIR / filename

        # Concatenate all audio chunks
        audio = np.concatenate(self.raw_audio)

        # Save to WAV file
        sf.write(filepath, audio, SAMPLE_RATE)

        self.last_recording_path = filepath
        print(f"💾 Saved: {filepath}")

    def cluster_unknowns(self):
        """Cluster unknown speakers and assign letters. Exclude conflicts."""
        # Exclude known speakers AND conflict segments
        unknowns = [s for s in self.segments
                    if not s['is_known'] and not s.get('is_conflict', False)]

        if len(unknowns) == 0:
            return 0

        if len(unknowns) == 1:
            unknowns[0]['speaker_label'] = 'Speaker A'
            return 1

        embeddings = np.array([s['embedding'] for s in unknowns])

        clustering = AgglomerativeClustering(
            n_clusters=None,
            distance_threshold=0.5,
            metric='cosine',
            linkage='average'
        )
        labels = clustering.fit_predict(embeddings)

        for i, s in enumerate(unknowns):
            s['speaker_label'] = f'Speaker {chr(65 + labels[i])}'

        # Mark conflict segments separately
        for s in self.segments:
            if s.get('is_conflict', False):
                s['speaker_label'] = s['speaker_name']  # Keep [A/B?] format

        # Also update known speakers
        for s in self.segments:
            if s['is_known']:
                s['speaker_label'] = s['speaker_name']

        return len(set(labels))

    def show_stats(self):
        """Show speed breakdown and speaker stats after stop."""
        if not self.segments:
            print("\n⚠️  No valid segments detected")
            return

        print("\n" + "=" * 60)
        print("SPEED BREAKDOWN")
        print("=" * 60)

        total_audio = sum(s['duration'] for s in self.segments)

        # Aggregate timings
        all_embed = [s['timings']['embedding'] for s in self.segments]
        all_trans = [s['timings']['transcribe'] for s in self.segments]
        all_match = [s['timings']['match'] for s in self.segments]

        print(f"\n{'Metric':<25} {'Total':<12} {'Avg/seg':<12} {'Min':<10} {'Max':<10}")
        print("-" * 70)
        print(f"{'Embedding':<25} {sum(all_embed):<12.0f} {np.mean(all_embed):<12.0f} {min(all_embed):<10.0f} {max(all_embed):<10.0f}")
        print(f"{'Transcription':<25} {sum(all_trans):<12.0f} {np.mean(all_trans):<12.0f} {min(all_trans):<10.0f} {max(all_trans):<10.0f}")
        print(f"{'Match':<25} {sum(all_match):<12.0f} {np.mean(all_match):<12.0f} {min(all_match):<10.0f} {max(all_match):<10.0f}")

        total_process = sum(sum(s['timings'].values()) for s in self.segments)
        print("-" * 70)
        print(f"{'TOTAL':<25} {total_process:<12.0f}ms")
        print(f"\nAudio duration: {total_audio:.1f}s")
        print(f"Processing time: {total_process/1000:.2f}s")
        if total_audio > 0:
            print(f"RTF: {total_process / (total_audio * 1000):.3f}")
            print(f"Speed: {total_audio * 1000 / total_process:.0f}x RT")

        # Speaker recognition stats
        print("\n" + "=" * 60)
        print("SPEAKER RECOGNITION")
        print("=" * 60)

        n_known = sum(1 for s in self.segments if s['is_known'])
        n_unknown = sum(1 for s in self.segments if not s['is_known'] and not s.get('is_conflict'))
        n_conflict = sum(1 for s in self.segments if s.get('is_conflict'))
        n_learned = sum(1 for s in self.segments if s.get('learned'))

        n_high = sum(1 for s in self.segments if s.get('confidence') == 'high')
        n_medium = sum(1 for s in self.segments if s.get('confidence') == 'medium')

        print(f"\nSegments: {len(self.segments)} total")
        print(f"  Known speakers:   {n_known} ({n_high} high conf, {n_medium} medium)")
        print(f"  Unknown speakers: {n_unknown}")
        print(f"  Conflicts:        {n_conflict}")
        print(f"  Auto-learned:     {n_learned} embeddings")

        # Show library status
        if self.library.speakers:
            print(f"\nVoice Library ({len(self.library.speakers)} speakers):")
            for name, profile in self.library.speakers.items():
                print(f"  {name}: {len(profile.core)} core, {len(profile.boundary)} boundary")

    def show_clustered_transcript(self):
        """Show final transcript with clustered speaker labels."""
        if not self.segments:
            return

        print("\n" + "=" * 60)
        print("TRANSCRIPT (with clustering)")
        print("=" * 60 + "\n")

        for s in self.segments:
            label = s.get('speaker_label', s.get('speaker_name', '???'))
            print(f"[{label}] ({s['start']:.1f}s-{s['end']:.1f}s) {s['text']}")

    def _select_diverse_embeddings(self, embeddings: list, max_count: int = 5) -> list:
        """Select most diverse embeddings using farthest-first traversal."""
        if len(embeddings) <= max_count:
            return embeddings

        selected = [embeddings[0]]
        remaining = embeddings[1:]

        while len(selected) < max_count and remaining:
            # Find embedding farthest from all selected
            best_emb = None
            best_min_dist = -1

            for emb in remaining:
                min_dist = min(cosine_distance(emb, s) for s in selected)
                if min_dist > best_min_dist:
                    best_min_dist = min_dist
                    best_emb = emb

            if best_emb is not None:
                selected.append(best_emb)
                remaining.remove(best_emb)

        return selected

    def prompt_naming(self):
        """
        Prompt user to name unknown speakers.

        Only asks about speakers with ≥3 segments (frequent speakers).
        Excludes conflict segments.
        Uses diversity-based selection when saving embeddings.
        """
        MIN_SEGMENTS_TO_NAME = 3  # Only ask about frequent speakers

        # Count segments per unknown label (exclude conflicts)
        label_counts = {}
        for s in self.segments:
            if not s['is_known'] and not s.get('is_conflict', False):
                label = s.get('speaker_label', 'Unknown')
                label_counts[label] = label_counts.get(label, 0) + 1

        # Filter to only frequent speakers
        frequent_labels = {label for label, count in label_counts.items()
                          if count >= MIN_SEGMENTS_TO_NAME}

        # Also show ignored speakers
        ignored_labels = {label for label, count in label_counts.items()
                         if count < MIN_SEGMENTS_TO_NAME}

        if not frequent_labels:
            if ignored_labels:
                print(f"\n⏭️  Skipped {len(ignored_labels)} infrequent speaker(s)")
            else:
                print("\n✅ All speakers are known!")
            return

        print("\n" + "=" * 60)
        print("NAME SPEAKERS (Enter to skip)")
        print(f"Showing speakers with ≥{MIN_SEGMENTS_TO_NAME} segments")
        print("=" * 60)

        for label in sorted(frequent_labels):
            samples = [s for s in self.segments
                      if s.get('speaker_label') == label and not s.get('is_conflict', False)]
            total_duration = sum(s['duration'] for s in samples)

            print(f"\n{label} ({len(samples)} segments, {total_duration:.1f}s):")
            for s in samples[:3]:
                text_preview = f"\"{s['text'][:50]}...\"" if len(s['text']) > 50 else f"\"{s['text']}\""
                print(f"  {text_preview}")

            name = input(f"Name for {label}: ").strip()

            if name:
                # Collect all embeddings from this speaker
                embeddings = [s['embedding'] for s in samples if s['embedding'] is not None]

                # Select most diverse embeddings
                diverse_embeddings = self._select_diverse_embeddings(embeddings)

                # Add to library
                for emb in diverse_embeddings:
                    self.library.add_embedding(name, emb)

                # Update labels
                for s in self.segments:
                    if s.get('speaker_label') == label:
                        s['speaker_label'] = name

                print(f"  ✅ Saved '{name}' with {len(diverse_embeddings)} diverse embeddings")

        if ignored_labels:
            print(f"\n⏭️  Skipped {len(ignored_labels)} infrequent speaker(s): {sorted(ignored_labels)}")

    def auto_learn_and_confirm_outliers(self):
        """
        Auto-learn from medium-confidence matches, only ask about outliers.

        Logic:
        1. Medium-confidence matches expand the voice boundary (valuable)
        2. Auto-learn those within reasonable distance from centroid
        3. Only ask user about far outliers (might be wrong OR very valuable)
        """
        OUTLIER_THRESHOLD = 2.0  # Ask about segments > 2σ from centroid

        # Group medium-confidence segments by speaker with distance info
        by_speaker = {}
        for i, s in enumerate(self.segments):
            if s['is_known'] and s['confidence'] == 'medium':
                name = s['speaker_name']
                profile = self.library.speakers.get(name)
                if profile and profile.centroid is not None:
                    dist = cosine_distance(s['embedding'], profile.centroid)
                    sigma_dist = dist / profile.std_dev if profile.std_dev > 0 else dist / 0.2
                else:
                    dist = 0.0
                    sigma_dist = 0.0

                if name not in by_speaker:
                    by_speaker[name] = {'auto': [], 'outliers': []}

                if sigma_dist <= OUTLIER_THRESHOLD:
                    by_speaker[name]['auto'].append((i, s, dist))
                else:
                    by_speaker[name]['outliers'].append((i, s, dist, sigma_dist))

        if not by_speaker:
            return

        total_auto_learned = 0
        total_outlier_learned = 0

        # Phase 1: Auto-learn from non-outliers
        for name, groups in by_speaker.items():
            if groups['auto']:
                embeddings = [s['embedding'] for _, s, _ in groups['auto'] if s['embedding'] is not None]
                diverse_embeddings = self._select_diverse_embeddings(embeddings, max_count=3)

                for emb in diverse_embeddings:
                    result = self.library.add_embedding(name, emb)
                    if result != "rejected":
                        total_auto_learned += 1

                # Mark as learned
                for seg_idx, s, _ in groups['auto']:
                    self.segments[seg_idx]['learned'] = True

        if total_auto_learned:
            print(f"\n📚 Auto-learned {total_auto_learned} boundary embeddings")

        # Phase 2: Ask about outliers (sorted by distance, furthest first)
        all_outliers = []
        for name, groups in by_speaker.items():
            for seg_idx, s, dist, sigma_dist in groups['outliers']:
                all_outliers.append((name, seg_idx, s, dist, sigma_dist))

        if not all_outliers:
            return

        # Sort by sigma distance (furthest first)
        all_outliers.sort(key=lambda x: x[4], reverse=True)

        print("\n" + "=" * 60)
        print("CONFIRM OUTLIERS (far from known voice pattern)")
        print("These could be misidentified OR valuable edge cases")
        print("=" * 60)

        for name, seg_idx, s, dist, sigma_dist in all_outliers:
            text_preview = s['text'][:50] + "..." if len(s['text']) > 50 else s['text']
            print(f"\n{name}? ({sigma_dist:.1f}σ from center)")
            print(f"  \"{text_preview}\"")

            response = input(f"  Learn this? [Y/n]: ").strip().lower()

            if response != 'n':
                # Force-add to boundary since user confirmed this outlier
                result = self.library.add_embedding(name, s['embedding'], force_boundary=True)
                if result != "rejected":
                    total_outlier_learned += 1
                    self.segments[seg_idx]['learned'] = True
                    print(f"  ✅ Learned ({result})")
                else:
                    print(f"  ⏭️  Rejected (too similar to existing)")
            else:
                print(f"  ⏭️  Skipped")

        if total_outlier_learned:
            print(f"\n📚 Outliers: {total_outlier_learned} new embeddings added")

    def process_file(self, file_path: str):
        """Process an audio file instead of live microphone input."""
        from pathlib import Path

        file_path = Path(file_path)
        if not file_path.exists():
            print(f"Error: File not found: {file_path}")
            return

        print("=" * 60)
        print("FILE VOICE PIPELINE (VAD Processing)")
        print("=" * 60)
        print(f"\n📁 Processing: {file_path.name}")

        self.load_models()

        # Load audio file
        print("\n[1/4] Loading audio...")
        try:
            audio, sr = sf.read(file_path)
        except Exception as e:
            print(f"Error reading file: {e}")
            print("Tip: For m4a files, convert to wav first:")
            print(f"  ffmpeg -i {file_path} -ar 16000 -ac 1 output.wav")
            return

        # Convert to mono if stereo
        if len(audio.shape) > 1:
            audio = audio.mean(axis=1)

        # Ensure float32 for model compatibility
        audio = audio.astype(np.float32)

        # Resample if needed
        if sr != SAMPLE_RATE:
            print(f"   Resampling from {sr}Hz to {SAMPLE_RATE}Hz...")
            import torchaudio.functional as F
            audio_tensor = torch.from_numpy(audio).float()
            audio_tensor = F.resample(audio_tensor, sr, SAMPLE_RATE)
            audio = audio_tensor.numpy()

        duration = len(audio) / SAMPLE_RATE
        print(f"   Duration: {duration:.1f}s, Sample rate: {SAMPLE_RATE}Hz")

        # Run VAD to find speech segments
        print("\n[2/4] Detecting speech segments (VAD)...")
        speech_timestamps = self.vad_utils[0](
            torch.from_numpy(audio).float(),
            self.vad_model,
            sampling_rate=SAMPLE_RATE,
            return_seconds=True
        )

        print(f"   Found {len(speech_timestamps)} speech segments")

        if not speech_timestamps:
            print("   No speech detected in file.")
            return

        # Process each segment
        print("\n[3/4] Processing segments...")
        print("-" * 60)

        self.segments = []
        for seg in speech_timestamps:
            start_time = seg['start']
            end_time = seg['end']

            # Extract segment audio (ensure float32 for model compatibility)
            start_sample = int(start_time * SAMPLE_RATE)
            end_sample = int(end_time * SAMPLE_RATE)
            segment_audio = audio[start_sample:end_sample].astype(np.float32)

            # Skip very short segments
            if len(segment_audio) < SAMPLE_RATE * 0.3:
                continue

            # Process segment (embedding + transcription + matching)
            self.process_segment(segment_audio, start_time, end_time)

        print("-" * 60)

        # Cluster and show results
        print("\n[4/4] Analyzing results...")

        if self.segments:
            n_clusters = self.cluster_unknowns()
            if n_clusters:
                print(f"\n📊 Clustered unknowns into {n_clusters} speakers")

            self.show_stats()
            self.show_clustered_transcript()
            self.prompt_naming()
            self.auto_learn_and_confirm_outliers()
        else:
            print("   No valid segments found.")

    def run(self):
        print("=" * 60)
        print("LIVE VOICE PIPELINE (VAD Streaming)")
        print("=" * 60)
        print("\n📢 Live output appears as you speak!")
        print("• Press Option to STOP\n")

        self.load_models()

        # Auto-start recording
        self.start_recording()

        def on_press(key):
            if key in (keyboard.Key.alt, keyboard.Key.alt_l, keyboard.Key.alt_r):
                # STOP
                self.stop_recording()

                if self.segments:
                    n_clusters = self.cluster_unknowns()
                    if n_clusters:
                        print(f"\n📊 Clustered unknowns into {n_clusters} speakers")

                    self.show_stats()
                    self.show_clustered_transcript()
                    self.prompt_naming()
                    self.auto_learn_and_confirm_outliers()

                return False  # Stop listener

        with keyboard.Listener(on_press=on_press) as listener:
            listener.join()


def main():
    import argparse

    parser = argparse.ArgumentParser(
        description="Live Voice Pipeline - VAD-Driven Speaker Diarization",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python live.py                    # Live microphone recording
  python live.py recording.wav      # Process audio file
  python live.py --file input.m4a   # Process audio file (explicit)
        """
    )
    parser.add_argument('file', nargs='?', help='Audio file to process (wav, m4a, mp3)')
    parser.add_argument('--file', '-f', dest='file_explicit', help='Audio file to process')

    args = parser.parse_args()

    # Get file path from either positional or explicit argument
    file_path = args.file or args.file_explicit

    pipeline = LivePipeline()

    if file_path:
        pipeline.process_file(file_path)
    else:
        pipeline.run()


if __name__ == "__main__":
    main()
