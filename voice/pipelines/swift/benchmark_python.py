#!/usr/bin/env python3
"""
Benchmark individual Python pipeline components for comparison with Swift.
"""
import torch
import torchaudio
import numpy as np
import time
from pathlib import Path

# Configuration
SAMPLE_RATE = 16000
N_MELS = 80
N_FFT = 400
HOP_LENGTH = 160
LFR_M = 7
LFR_N = 6

def benchmark_component(name, func, *args):
    """Benchmark a component and return timing."""
    start = time.time()
    result = func(*args)
    elapsed = (time.time() - start) * 1000  # Convert to ms
    return elapsed, result

def apply_lfr(mel):
    """Apply LFR transform."""
    T = mel.shape[0]
    lfr_frames = []
    i = 0
    while i + LFR_M <= T:
        frame = mel[i:i+LFR_M].reshape(-1)  # Stack 7 frames
        lfr_frames.append(frame)
        i += LFR_N

    if lfr_frames:
        return np.stack(lfr_frames)
    return np.array([])

def main():
    print("=== Python Pipeline Component Benchmark ===\n")

    # Load audio
    audio_path = "/Users/zhengyishen/Codes/claude-code-voice-isolation/voice/test_recording.wav"
    waveform, sample_rate = torchaudio.load(audio_path)

    # Convert to mono and resample
    if waveform.shape[0] > 1:
        waveform = waveform.mean(dim=0, keepdim=True)
    if sample_rate != SAMPLE_RATE:
        resampler = torchaudio.transforms.Resample(sample_rate, SAMPLE_RATE)
        waveform = resampler(waveform)

    audio_samples = waveform.shape[1]
    audio_duration = audio_samples / SAMPLE_RATE
    print(f"Audio: {audio_samples} samples ({audio_duration:.1f}s)\n")

    timings = {}

    # 1. Mel Spectrogram (includes FFT)
    print("1️⃣ Mel Spectrogram (with FFT)...")
    mel_transform = torchaudio.transforms.MelSpectrogram(
        sample_rate=SAMPLE_RATE,
        n_mels=N_MELS,
        n_fft=N_FFT,
        hop_length=HOP_LENGTH,
        win_length=N_FFT,
        window_fn=torch.hamming_window,
        power=1.0,  # magnitude
        center=True,
        pad_mode='reflect'
    )

    elapsed, mel = benchmark_component("mel_spectrogram",
                                       lambda w: mel_transform(w),
                                       waveform)
    timings['Mel Spectrogram (with FFT)'] = elapsed
    print(f"   Time: {elapsed:.1f}ms")
    print(f"   Shape: {mel.shape}")

    # 2. Log transform
    print("\n2️⃣ Log Transform...")
    mel_numpy = mel.squeeze(0).T.numpy()  # (time, freq)

    elapsed, log_mel = benchmark_component("log_transform",
                                           lambda m: np.log(np.clip(m, a_min=1e-10, a_max=None)),
                                           mel_numpy)
    timings['Log Transform'] = elapsed
    print(f"   Time: {elapsed:.1f}ms")

    # 3. LFR Transform
    print("\n3️⃣ LFR Transform...")
    elapsed, lfr = benchmark_component("lfr_transform", apply_lfr, log_mel)
    timings['LFR Transform'] = elapsed
    print(f"   Time: {elapsed:.1f}ms")
    print(f"   Shape: {lfr.shape}")

    # 4. CoreML Inference (load Python features and time only the inference)
    print("\n4️⃣ CoreML Inference Comparison...")
    print("   (Loading Python pre-computed features)")

    # Load the same features we saved earlier
    features_path = "/Users/zhengyishen/Codes/claude-code-voice-isolation/voice/swift-pipeline-test/python_features.bin"
    if Path(features_path).exists():
        features = np.fromfile(features_path, dtype=np.float32).reshape(500, 560)

        try:
            import coremltools as ct

            # Try multiple model paths
            model_paths = [
                "/Users/zhengyishen/Codes/claude-code-voice-isolation/voice/YouPu/Sources/YouPu/Models/sensevoice-500-itn.mlmodelc",
                "/Users/zhengyishen/Codes/claude-code/voice/transcription/models/sensevoice-500-itn.mlmodelc"
            ]

            model_path = None
            for path in model_paths:
                if Path(path).exists():
                    model_path = path
                    break

            if not model_path:
                print(f"   ⚠️  Model not found at any expected path")
            else:
                print(f"   Loading model from: {Path(model_path).name}")

                start = time.time()
                model = ct.models.MLModel(model_path)
                load_time = (time.time() - start) * 1000

                # Prepare input
                input_dict = {'audio_features': features.reshape(1, 500, 560).astype(np.float32)}

                # Run inference
                start = time.time()
                output = model.predict(input_dict)
                infer_time = (time.time() - start) * 1000

                timings['Model Loading'] = load_time
                timings['CoreML Inference'] = infer_time
                print(f"   Model loading: {load_time:.1f}ms")
                print(f"   Inference time: {infer_time:.1f}ms")
                print(f"   Output shape: {output['logits'].shape if 'logits' in output else 'unknown'}")

        except Exception as e:
            print(f"   ⚠️  Could not run CoreML: {e}")
            import traceback
            traceback.print_exc()
    else:
        print(f"   ⚠️  Features file not found")

    # Summary
    print("\n" + "="*60)
    print("PYTHON PERFORMANCE SUMMARY")
    print("="*60)
    print()
    print(f"{'Component':<35} {'Time (ms)':>12} {'Per-frame':>12}")
    print("-"*60)

    total_time = 0
    for name, time_ms in timings.items():
        total_time += time_ms
        if 'Mel' in name:
            num_frames = mel.shape[2]  # Time dimension
            per_frame = time_ms / num_frames
            print(f"{name:<35} {time_ms:>12.1f} {per_frame:>11.3f}ms")
        else:
            print(f"{name:<35} {time_ms:>12.1f} {'-':>12}")

    print("-"*60)
    print(f"{'TOTAL':<35} {total_time:>12.1f}")
    print()
    print(f"Audio duration: {audio_duration:.1f}s")
    print(f"Processing time: {total_time/1000:.1f}s")
    print(f"Real-time factor: {(total_time/1000)/audio_duration:.2f}x")
    print()
    print("="*60)

if __name__ == '__main__':
    main()
