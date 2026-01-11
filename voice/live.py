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
sys.path.insert(0, '.')
sys.path.insert(0, 'transcription')

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


class VoiceLibrary:
    """Persistent voice library for known speakers."""

    def __init__(self, path=LIBRARY_PATH):
        self.path = path
        self.speakers = {}
        self.load()

    def load(self):
        if self.path.exists():
            with open(self.path) as f:
                data = json.load(f)
                for name, embs in data.items():
                    self.speakers[name] = [np.array(e) for e in embs]
            print(f"  📂 Loaded {len(self.speakers)} speakers: {list(self.speakers.keys())}")

    def save(self):
        data = {name: [e.tolist() for e in embs] for name, embs in self.speakers.items()}
        with open(self.path, 'w') as f:
            json.dump(data, f)

    def add_embedding(self, name, embedding):
        if name not in self.speakers:
            self.speakers[name] = []
        self.speakers[name].append(embedding)
        self.save()

    def match(self, embedding, threshold=0.4):
        if not self.speakers:
            return None, 0.0

        emb_norm = embedding / np.linalg.norm(embedding)
        best_name, best_score = None, -1

        for name, embs in self.speakers.items():
            for stored_emb in embs:
                stored_norm = stored_emb / np.linalg.norm(stored_emb)
                score = np.dot(emb_norm, stored_norm)
                if score > best_score:
                    best_score = score
                    best_name = name

        if best_score >= threshold:
            return best_name, best_score
        return None, best_score


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
        """Process segment with parallel embedding + transcription."""
        timings = {}

        def do_embedding():
            t = time.time()
            emb = self.extract_embedding(audio)
            return emb, (time.time() - t) * 1000

        def do_transcription():
            t = time.time()
            text, _ = self.asr_model.transcribe_audio(audio)
            return text.strip(), (time.time() - t) * 1000

        # Run in parallel
        emb_future = self.executor.submit(do_embedding)
        trans_future = self.executor.submit(do_transcription)

        embedding, emb_time = emb_future.result()
        text, trans_time = trans_future.result()

        timings['embedding'] = emb_time
        timings['transcribe'] = trans_time

        # Filter invalid transcripts
        if not is_valid_transcript(text):
            return None

        # Match speaker
        t0 = time.time()
        name, score = self.library.match(embedding)
        is_known = name is not None
        timings['match'] = (time.time() - t0) * 1000

        # Store segment
        segment = {
            'start': start_time,
            'end': end_time,
            'text': text,
            'embedding': embedding,
            'speaker_name': name,
            'match_score': score,
            'is_known': is_known,
            'timings': timings,
            'duration': end_time - start_time
        }
        self.segments.append(segment)

        # LIVE OUTPUT
        speaker_label = name if is_known else "???"
        total_time = sum(timings.values())
        print(f"[{speaker_label}] ({start_time:.1f}s-{end_time:.1f}s) {text}  [{total_time:.0f}ms]")

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
        """Cluster unknown speakers and assign letters."""
        unknowns = [s for s in self.segments if not s['is_known']]

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

        # Also update known speakers
        for s in self.segments:
            if s['is_known']:
                s['speaker_label'] = s['speaker_name']

        return len(set(labels))

    def show_stats(self):
        """Show speed breakdown after stop."""
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

    def prompt_naming(self):
        """Prompt user to name unknown speakers."""
        unknown_labels = set()
        for s in self.segments:
            if not s['is_known']:
                unknown_labels.add(s.get('speaker_label', 'Unknown'))

        if not unknown_labels:
            print("\n✅ All speakers are known!")
            return

        print("\n" + "=" * 60)
        print("NAME SPEAKERS (Enter to skip)")
        print("=" * 60)

        for label in sorted(unknown_labels):
            samples = [s for s in self.segments if s.get('speaker_label') == label]
            print(f"\n{label} said:")
            for s in samples[:2]:
                print(f"  \"{s['text'][:60]}...\"" if len(s['text']) > 60 else f"  \"{s['text']}\"")

            name = input(f"Name for {label}: ").strip()

            if name:
                for s in self.segments:
                    if s.get('speaker_label') == label:
                        s['speaker_label'] = name
                        if s['embedding'] is not None:
                            self.library.add_embedding(name, s['embedding'])
                print(f"  ✅ Saved '{name}' to library")

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

                return False  # Stop listener

        with keyboard.Listener(on_press=on_press) as listener:
            listener.join()


def main():
    pipeline = LivePipeline()
    pipeline.run()


if __name__ == "__main__":
    main()
