#!/usr/bin/env python3
"""
Comprehensive Python vs Swift pipeline comparison.
Exports intermediate values and timing for each stage.
"""
import torch
import torchaudio
import numpy as np
import time
import json
from pathlib import Path

# Configuration (must match Swift)
SAMPLE_RATE = 16000
N_MELS = 80
N_FFT = 400
HOP_LENGTH = 160
LFR_M = 7
LFR_N = 6
FIXED_FRAMES = 500

def apply_lfr(mel):
    """Apply LFR transform."""
    T = mel.shape[0]
    lfr_frames = []
    i = 0
    while i + LFR_M <= T:
        frame = mel[i:i+LFR_M].reshape(-1)
        lfr_frames.append(frame)
        i += LFR_N
    if lfr_frames:
        return np.stack(lfr_frames)
    return np.array([])

def pad_to_fixed(features, fixed_frames=500):
    """Pad or truncate to fixed number of frames."""
    if len(features) < fixed_frames:
        padding = np.zeros((fixed_frames - len(features), features.shape[1]), dtype=np.float32)
        return np.vstack([features, padding])
    return features[:fixed_frames]

def main():
    print("=" * 70)
    print("PYTHON vs SWIFT PIPELINE COMPARISON")
    print("=" * 70)
    print()

    # Audio path
    audio_path = "/Users/zhengyishen/Codes/claude-code-voice-isolation/voice/test_recording.wav"
    output_dir = Path("/Users/zhengyishen/Codes/claude-code-voice-isolation/voice/swift-pipeline-test/comparison")
    output_dir.mkdir(exist_ok=True)

    results = {
        'python': {'timing': {}, 'shapes': {}, 'values': {}},
        'config': {
            'sample_rate': SAMPLE_RATE,
            'n_mels': N_MELS,
            'n_fft': N_FFT,
            'hop_length': HOP_LENGTH,
            'lfr_m': LFR_M,
            'lfr_n': LFR_N,
        }
    }

    # ========== STAGE 1: Audio Loading ==========
    print("STAGE 1: Audio Loading")
    print("-" * 40)

    start = time.time()
    waveform, sample_rate = torchaudio.load(audio_path)
    load_time = (time.time() - start) * 1000

    # Convert to mono
    if waveform.shape[0] > 1:
        waveform = waveform.mean(dim=0, keepdim=True)

    # Resample if needed
    if sample_rate != SAMPLE_RATE:
        start = time.time()
        resampler = torchaudio.transforms.Resample(sample_rate, SAMPLE_RATE)
        waveform = resampler(waveform)
        resample_time = (time.time() - start) * 1000
        load_time += resample_time
        print(f"  Resampled: {sample_rate}Hz → {SAMPLE_RATE}Hz ({resample_time:.1f}ms)")

    audio = waveform.squeeze(0).numpy()
    audio_duration = len(audio) / SAMPLE_RATE

    results['python']['timing']['1_audio_load'] = load_time
    results['python']['shapes']['audio'] = list(audio.shape)
    results['python']['values']['audio_first10'] = audio[:10].tolist()
    results['python']['values']['audio_stats'] = {
        'min': float(audio.min()),
        'max': float(audio.max()),
        'mean': float(audio.mean()),
    }

    print(f"  Samples: {len(audio)} ({audio_duration:.2f}s)")
    print(f"  Time: {load_time:.1f}ms")
    print(f"  First 5: {audio[:5]}")
    print()

    # ========== STAGE 2: STFT + Mel Spectrogram ==========
    print("STAGE 2: STFT + Mel Spectrogram")
    print("-" * 40)

    mel_transform = torchaudio.transforms.MelSpectrogram(
        sample_rate=SAMPLE_RATE,
        n_mels=N_MELS,
        n_fft=N_FFT,
        hop_length=HOP_LENGTH,
        win_length=N_FFT,
        window_fn=torch.hamming_window,
        power=1.0,  # magnitude, not power
        center=True,
        pad_mode='reflect'
    )

    start = time.time()
    mel = mel_transform(waveform)
    mel_time = (time.time() - start) * 1000

    mel_numpy = mel.squeeze(0).T.numpy()  # (time, freq)

    results['python']['timing']['2_mel_spectrogram'] = mel_time
    results['python']['shapes']['mel'] = list(mel_numpy.shape)
    results['python']['values']['mel_first_frame'] = mel_numpy[0, :10].tolist()
    results['python']['values']['mel_stats'] = {
        'min': float(mel_numpy.min()),
        'max': float(mel_numpy.max()),
        'mean': float(mel_numpy.mean()),
    }

    print(f"  Shape: {mel_numpy.shape}")
    print(f"  Time: {mel_time:.1f}ms")
    print(f"  First frame (first 10): {mel_numpy[0, :10]}")
    print(f"  Stats: min={mel_numpy.min():.6f}, max={mel_numpy.max():.6f}")
    print()

    # ========== STAGE 3: Log Transform ==========
    print("STAGE 3: Log Transform")
    print("-" * 40)

    start = time.time()
    log_mel = np.log(np.clip(mel_numpy, a_min=1e-10, a_max=None))
    log_time = (time.time() - start) * 1000

    results['python']['timing']['3_log_transform'] = log_time
    results['python']['shapes']['log_mel'] = list(log_mel.shape)
    results['python']['values']['log_mel_first_frame'] = log_mel[0, :10].tolist()
    results['python']['values']['log_mel_stats'] = {
        'min': float(log_mel.min()),
        'max': float(log_mel.max()),
        'mean': float(log_mel.mean()),
    }

    print(f"  Shape: {log_mel.shape}")
    print(f"  Time: {log_time:.1f}ms")
    print(f"  First frame (first 10): {log_mel[0, :10]}")
    print(f"  Stats: min={log_mel.min():.3f}, max={log_mel.max():.3f}")
    print()

    # ========== STAGE 4: LFR Transform ==========
    print("STAGE 4: LFR Transform")
    print("-" * 40)

    start = time.time()
    lfr = apply_lfr(log_mel)
    lfr_time = (time.time() - start) * 1000

    results['python']['timing']['4_lfr_transform'] = lfr_time
    results['python']['shapes']['lfr'] = list(lfr.shape)
    results['python']['values']['lfr_first_frame'] = lfr[0, :10].tolist()

    print(f"  Shape: {lfr.shape}")
    print(f"  Time: {lfr_time:.1f}ms")
    print(f"  First frame (first 10): {lfr[0, :10]}")
    print()

    # ========== STAGE 5: Padding ==========
    print("STAGE 5: Pad to Fixed Frames")
    print("-" * 40)

    start = time.time()
    padded = pad_to_fixed(lfr, FIXED_FRAMES)
    pad_time = (time.time() - start) * 1000

    results['python']['timing']['5_padding'] = pad_time
    results['python']['shapes']['padded'] = list(padded.shape)

    print(f"  Shape: {padded.shape}")
    print(f"  Time: {pad_time:.1f}ms")
    print()

    # ========== STAGE 6: CoreML Inference ==========
    print("STAGE 6: CoreML Inference")
    print("-" * 40)

    try:
        import coremltools as ct

        model_path = "/Users/zhengyishen/Codes/claude-code-voice-isolation/voice/YouPu/Sources/YouPu/Models/sensevoice-500-itn.mlmodelc"

        if Path(model_path).exists():
            start = time.time()
            model = ct.models.MLModel(model_path)
            model_load_time = (time.time() - start) * 1000

            input_dict = {'audio_features': padded.reshape(1, 500, 560).astype(np.float32)}

            start = time.time()
            output = model.predict(input_dict)
            infer_time = (time.time() - start) * 1000

            logits = output['logits']

            results['python']['timing']['6a_model_load'] = model_load_time
            results['python']['timing']['6b_inference'] = infer_time
            results['python']['shapes']['logits'] = list(logits.shape)
            results['python']['values']['logits_first_frame'] = logits[0, 0, :10].tolist()

            print(f"  Model load: {model_load_time:.1f}ms")
            print(f"  Inference: {infer_time:.1f}ms")
            print(f"  Output shape: {logits.shape}")
            print(f"  First frame (first 10): {logits[0, 0, :10]}")

            # ========== STAGE 7: CTC Decoding ==========
            print()
            print("STAGE 7: CTC Greedy Decoding")
            print("-" * 40)

            start = time.time()
            tokens = []
            prev_token = -1
            for t in range(logits.shape[1]):
                max_idx = np.argmax(logits[0, t, :])
                if max_idx != 0 and max_idx != prev_token:
                    tokens.append(int(max_idx))
                prev_token = max_idx
            ctc_time = (time.time() - start) * 1000

            results['python']['timing']['7_ctc_decode'] = ctc_time
            results['python']['values']['tokens'] = tokens
            results['python']['values']['token_count'] = len(tokens)

            print(f"  Time: {ctc_time:.1f}ms")
            print(f"  Token count: {len(tokens)}")
            print(f"  First 20 tokens: {tokens[:20]}")

        else:
            print(f"  ⚠️ Model not found")

    except Exception as e:
        print(f"  ⚠️ Error: {e}")

    # ========== SUMMARY ==========
    print()
    print("=" * 70)
    print("PYTHON TIMING SUMMARY")
    print("=" * 70)
    print()
    print(f"{'Stage':<35} {'Time (ms)':>12}")
    print("-" * 50)

    total = 0
    for key, val in results['python']['timing'].items():
        print(f"{key:<35} {val:>12.2f}")
        total += val

    print("-" * 50)
    print(f"{'TOTAL':<35} {total:>12.2f}")
    print()
    print(f"Audio duration: {audio_duration:.2f}s")
    print(f"Processing time: {total/1000:.3f}s")
    print(f"Real-time factor: {(total/1000)/audio_duration:.3f}x")
    print()

    # Save results
    results_path = output_dir / "python_results.json"
    with open(results_path, 'w') as f:
        json.dump(results, f, indent=2)
    print(f"Results saved to: {results_path}")

if __name__ == '__main__':
    main()
