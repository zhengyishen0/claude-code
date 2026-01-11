#!/usr/bin/env python3
"""Compare audio characteristics between baseline and voice-isolated recordings."""

import sys
import numpy as np
import soundfile as sf
from pathlib import Path


def analyze_audio(filepath: str) -> dict:
    """Analyze audio file and return statistics."""
    audio, sr = sf.read(filepath)

    # Ensure mono
    if len(audio.shape) > 1:
        audio = audio[:, 0]

    # Basic statistics
    rms = np.sqrt(np.mean(audio ** 2))
    peak = np.max(np.abs(audio))
    db_rms = 20 * np.log10(rms + 1e-10)
    db_peak = 20 * np.log10(peak + 1e-10)

    # Dynamic range
    # Split into frames and analyze
    frame_size = int(0.025 * sr)  # 25ms frames
    hop_size = int(0.010 * sr)    # 10ms hop

    frame_rms = []
    for i in range(0, len(audio) - frame_size, hop_size):
        frame = audio[i:i + frame_size]
        frame_rms.append(np.sqrt(np.mean(frame ** 2)))

    frame_rms = np.array(frame_rms)
    frame_db = 20 * np.log10(frame_rms + 1e-10)

    # Noise floor estimate (10th percentile of frame RMS)
    noise_floor_db = np.percentile(frame_db, 10)

    # Signal estimate (90th percentile)
    signal_db = np.percentile(frame_db, 90)

    # Estimated SNR
    snr_estimate = signal_db - noise_floor_db

    return {
        'duration': len(audio) / sr,
        'sample_rate': sr,
        'rms': rms,
        'rms_db': db_rms,
        'peak': peak,
        'peak_db': db_peak,
        'noise_floor_db': noise_floor_db,
        'signal_db': signal_db,
        'snr_estimate_db': snr_estimate,
        'dynamic_range_db': np.max(frame_db) - np.min(frame_db),
        'std_db': np.std(frame_db),
    }


def print_comparison(baseline: dict, isolated: dict):
    """Print comparison table."""
    print("\n" + "=" * 70)
    print("VOICE ISOLATION COMPARISON REPORT")
    print("=" * 70)

    print(f"\n{'Metric':<25} {'Baseline':>15} {'Isolated':>15} {'Diff':>12}")
    print("-" * 70)

    def fmt(val, decimals=2):
        if isinstance(val, float):
            return f"{val:.{decimals}f}"
        return str(val)

    def diff(b, i, unit=""):
        d = i - b
        sign = "+" if d > 0 else ""
        return f"{sign}{d:.2f}{unit}"

    rows = [
        ("Duration (s)", baseline['duration'], isolated['duration'], ""),
        ("Sample Rate (Hz)", baseline['sample_rate'], isolated['sample_rate'], ""),
        ("RMS Level (dB)", baseline['rms_db'], isolated['rms_db'], " dB"),
        ("Peak Level (dB)", baseline['peak_db'], isolated['peak_db'], " dB"),
        ("Noise Floor (dB)", baseline['noise_floor_db'], isolated['noise_floor_db'], " dB"),
        ("Signal Level (dB)", baseline['signal_db'], isolated['signal_db'], " dB"),
        ("Est. SNR (dB)", baseline['snr_estimate_db'], isolated['snr_estimate_db'], " dB"),
        ("Dynamic Range (dB)", baseline['dynamic_range_db'], isolated['dynamic_range_db'], " dB"),
        ("Level Std Dev (dB)", baseline['std_db'], isolated['std_db'], " dB"),
    ]

    for name, b_val, i_val, unit in rows:
        if isinstance(b_val, float):
            print(f"{name:<25} {b_val:>15.2f} {i_val:>15.2f} {diff(b_val, i_val, unit):>12}")
        else:
            print(f"{name:<25} {b_val:>15} {i_val:>15} {'':>12}")

    print("\n" + "-" * 70)
    print("INTERPRETATION:")
    print("-" * 70)

    noise_diff = isolated['noise_floor_db'] - baseline['noise_floor_db']
    if noise_diff < -3:
        print(f"✓ Voice Isolation REDUCED noise floor by {-noise_diff:.1f} dB")
    elif noise_diff > 3:
        print(f"✗ Voice Isolation INCREASED noise floor by {noise_diff:.1f} dB")
    else:
        print(f"○ Noise floor similar (diff: {noise_diff:.1f} dB)")

    snr_diff = isolated['snr_estimate_db'] - baseline['snr_estimate_db']
    if snr_diff > 3:
        print(f"✓ Voice Isolation IMPROVED SNR by {snr_diff:.1f} dB")
    elif snr_diff < -3:
        print(f"✗ Voice Isolation DEGRADED SNR by {-snr_diff:.1f} dB")
    else:
        print(f"○ SNR similar (diff: {snr_diff:.1f} dB)")

    rms_diff = isolated['rms_db'] - baseline['rms_db']
    if rms_diff < -6:
        print(f"✓ Overall level reduced by {-rms_diff:.1f} dB (noise suppression active)")
    elif rms_diff > 6:
        print(f"○ Overall level increased by {rms_diff:.1f} dB")

    print("=" * 70)


if __name__ == "__main__":
    base_dir = Path("/Users/zhengyishen/Codes/claude-code-voice-isolation/voice/recordings")

    baseline_path = base_dir / "baseline.wav"
    isolated_path = base_dir / "isolated.wav"

    if not baseline_path.exists() or not isolated_path.exists():
        print("Error: Recording files not found")
        print(f"Expected: {baseline_path}")
        print(f"Expected: {isolated_path}")
        sys.exit(1)

    print(f"Analyzing: {baseline_path.name}")
    baseline = analyze_audio(str(baseline_path))

    print(f"Analyzing: {isolated_path.name}")
    isolated = analyze_audio(str(isolated_path))

    print_comparison(baseline, isolated)
