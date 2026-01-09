#!/usr/bin/env python3
"""
Test the CoreML SepReformer model with various audio samples.

Tests performance and separation quality on mixtures of different lengths.
"""

import sys
import time
import numpy as np
import soundfile as sf
import coremltools as ct
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
MODEL_PATH = SCRIPT_DIR / "models" / "SepReformer_Base.mlpackage"
TEST_AUDIO_DIR = SCRIPT_DIR / "test_audio"
OUTPUT_DIR = SCRIPT_DIR / "test_output"

# Model expects 4 seconds at 8kHz
CHUNK_SIZE = 32000  # 4 seconds
SAMPLE_RATE = 8000


def load_audio(path):
    """Load audio file and resample to 8kHz if needed."""
    audio, sr = sf.read(path)

    # Convert stereo to mono if needed
    if len(audio.shape) > 1:
        audio = audio.mean(axis=1)

    # Resample if needed
    if sr != SAMPLE_RATE:
        import scipy.signal as signal
        num_samples = int(len(audio) * SAMPLE_RATE / sr)
        audio = signal.resample(audio, num_samples)

    return audio.astype(np.float32)


def process_audio(model, audio):
    """
    Process audio through the CoreML model in chunks.

    Returns:
        speaker1, speaker2: Separated audio for each speaker
    """
    # Pad to multiple of chunk size
    pad_len = (CHUNK_SIZE - len(audio) % CHUNK_SIZE) % CHUNK_SIZE
    if pad_len > 0:
        audio = np.pad(audio, (0, pad_len))

    num_chunks = len(audio) // CHUNK_SIZE
    speaker1_chunks = []
    speaker2_chunks = []

    for i in range(num_chunks):
        chunk = audio[i * CHUNK_SIZE:(i + 1) * CHUNK_SIZE]
        chunk_input = chunk.reshape(1, -1)

        # Run inference
        output = model.predict({"audio_input": chunk_input})

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


def compute_si_snr(reference, estimate):
    """Compute Scale-Invariant Signal-to-Noise Ratio (SI-SNR)."""
    # Zero-mean normalization
    reference = reference - np.mean(reference)
    estimate = estimate - np.mean(estimate)

    # Compute SI-SNR
    dot = np.sum(reference * estimate)
    s_target = dot * reference / (np.sum(reference ** 2) + 1e-8)
    e_noise = estimate - s_target

    si_snr = 10 * np.log10(np.sum(s_target ** 2) / (np.sum(e_noise ** 2) + 1e-8) + 1e-8)
    return si_snr


def test_model(model, mixture_path, ref1_path=None, ref2_path=None):
    """Test the model on a mixture file."""
    # Load mixture
    mixture = load_audio(mixture_path)
    duration = len(mixture) / SAMPLE_RATE

    print(f"\n{'='*60}")
    print(f"Testing: {mixture_path.name}")
    print(f"Duration: {duration:.2f}s ({len(mixture)} samples)")
    print(f"Chunks: {int(np.ceil(len(mixture) / CHUNK_SIZE))}")

    # Process through model
    start_time = time.time()
    speaker1, speaker2 = process_audio(model, mixture)
    elapsed = time.time() - start_time

    rtf = elapsed / duration
    print(f"\nPerformance:")
    print(f"  Processing time: {elapsed:.2f}s")
    print(f"  RTF: {rtf:.3f} ({1/rtf:.1f}x real-time)")

    # Save outputs
    output_base = OUTPUT_DIR / mixture_path.stem
    sf.write(f"{output_base}_speaker1.wav", speaker1, SAMPLE_RATE)
    sf.write(f"{output_base}_speaker2.wav", speaker2, SAMPLE_RATE)
    print(f"\nSaved: {output_base}_speaker1.wav, {output_base}_speaker2.wav")

    # Compute quality metrics if references provided
    if ref1_path and ref2_path:
        ref1 = load_audio(ref1_path)
        ref2 = load_audio(ref2_path)

        # Trim to same length
        min_len = min(len(speaker1), len(ref1), len(ref2))
        speaker1 = speaker1[:min_len]
        speaker2 = speaker2[:min_len]
        ref1 = ref1[:min_len]
        ref2 = ref2[:min_len]

        # Try both permutations (model might swap speakers)
        si_snr_1_1 = compute_si_snr(ref1, speaker1)
        si_snr_1_2 = compute_si_snr(ref1, speaker2)
        si_snr_2_1 = compute_si_snr(ref2, speaker1)
        si_snr_2_2 = compute_si_snr(ref2, speaker2)

        # Pick best permutation
        perm1_score = si_snr_1_1 + si_snr_2_2
        perm2_score = si_snr_1_2 + si_snr_2_1

        if perm1_score >= perm2_score:
            print(f"\nQuality (SI-SNR):")
            print(f"  Speaker 1: {si_snr_1_1:.2f} dB")
            print(f"  Speaker 2: {si_snr_2_2:.2f} dB")
            print(f"  Average: {(si_snr_1_1 + si_snr_2_2)/2:.2f} dB")
        else:
            print(f"\nQuality (SI-SNR) [speakers swapped]:")
            print(f"  Speaker 1: {si_snr_1_2:.2f} dB")
            print(f"  Speaker 2: {si_snr_2_1:.2f} dB")
            print(f"  Average: {(si_snr_1_2 + si_snr_2_1)/2:.2f} dB")

    return elapsed, rtf


def main():
    print("=" * 60)
    print("SepReformer CoreML Model Test")
    print("=" * 60)

    # Check model exists
    if not MODEL_PATH.exists():
        print(f"ERROR: Model not found at {MODEL_PATH}")
        sys.exit(1)

    # Create output directory
    OUTPUT_DIR.mkdir(exist_ok=True)

    # Load model
    print(f"\nLoading model from {MODEL_PATH}...")
    model = ct.models.MLModel(str(MODEL_PATH))
    print("Model loaded!")

    # Test files
    tests = [
        # (mixture_path, ref1_path, ref2_path)
        ("aalto_mixture.wav", "aalto_speaker1.wav", "aalto_speaker2.wav"),
        ("osr_mixture_33s.wav", "osr_speaker1.wav", "osr_speaker2.wav"),
        ("osr_mixture_60s.wav", None, None),  # No exact refs for looped version
        ("osr_mixture_120s.wav", None, None),  # 2 minutes
    ]

    results = []

    for test in tests:
        mixture_path = TEST_AUDIO_DIR / test[0]
        if not mixture_path.exists():
            print(f"\nSkipping {test[0]} - file not found")
            continue

        ref1_path = TEST_AUDIO_DIR / test[1] if test[1] else None
        ref2_path = TEST_AUDIO_DIR / test[2] if test[2] else None

        if ref1_path and not ref1_path.exists():
            ref1_path = None
            ref2_path = None

        elapsed, rtf = test_model(model, mixture_path, ref1_path, ref2_path)
        results.append((test[0], elapsed, rtf))

    # Summary
    print("\n" + "=" * 60)
    print("SUMMARY")
    print("=" * 60)
    print(f"{'File':<30} {'Time (s)':<12} {'RTF':<10} {'Speed':<10}")
    print("-" * 60)
    for name, elapsed, rtf in results:
        print(f"{name:<30} {elapsed:<12.2f} {rtf:<10.3f} {1/rtf:.1f}x")

    print("\nAll outputs saved to:", OUTPUT_DIR)


if __name__ == "__main__":
    main()
