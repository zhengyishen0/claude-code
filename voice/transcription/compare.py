#!/usr/bin/env python3
"""
Compare SenseVoice: CoreML (250, 500, ITN variants) vs Metal.

Usage:
    python3 compare.py [audio_file]
    python3 compare.py                       # Interactive hold-to-record
    python3 compare.py test/chinese-14s.wav  # Test specific file

Compares 5 models:
  - CoreML-250 (ANE, no punctuation)
  - CoreML-500 (ANE, no punctuation)
  - CoreML-250+ITN (ANE, with punctuation)
  - CoreML-500+ITN (ANE, with punctuation)
  - Metal (GPU, via sensevoice.cpp)

Shows output immediately as each model finishes to demonstrate speed difference.
"""

import subprocess
import tempfile
import time
import os
import sys
import argparse
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
import threading

# Paths
SCRIPT_DIR = Path(__file__).parent
SENSEVOICE_CPP = SCRIPT_DIR.parent / "sensevoice-cpp" / "build" / "bin" / "sense-voice-main"
SENSEVOICE_MODEL = SCRIPT_DIR.parent / "sensevoice-cpp" / "models" / "sense-voice-small-fp16.gguf"

# Global state for interactive mode
recording_process = None
audio_file = None
is_recording = False

# Models (loaded lazily)
models = {}
models_lock = threading.Lock()


def get_coreml_model(frames: int, itn: bool = False):
    """Get or load a CoreML model (thread-safe)."""
    key = (frames, itn)
    with models_lock:
        if key not in models:
            from sensevoice_coreml import SenseVoiceCoreML
            models[key] = SenseVoiceCoreML(frames=frames, itn=itn)
        return models[key]


def convert_to_16bit(input_path: str) -> str:
    """Convert audio to 16-bit PCM WAV for sensevoice.cpp compatibility."""
    output_path = tempfile.NamedTemporaryFile(suffix=".wav", delete=False).name
    subprocess.run(
        ["ffmpeg", "-y", "-i", input_path, "-acodec", "pcm_s16le", "-ar", "16000", "-ac", "1", output_path],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=True
    )
    return output_path


def transcribe_metal(audio_path: str, print_immediately: bool = True) -> tuple[str, float, str]:
    """Transcribe using Metal (sensevoice.cpp)."""
    name = "Metal (GPU)"

    # Convert to 16-bit
    temp_path = convert_to_16bit(audio_path)

    start = time.perf_counter()
    result = subprocess.run(
        [str(SENSEVOICE_CPP), "-m", str(SENSEVOICE_MODEL), temp_path, "-t", "4"],
        capture_output=True,
        text=True
    )
    elapsed = time.perf_counter() - start

    # Clean up temp file
    os.unlink(temp_path)

    # Parse output
    lines = []
    for line in result.stdout.split("\n"):
        if line.startswith("[") and "]" in line:
            text = line.split("]", 1)[1].strip()
            if text:
                lines.append(text)
    text = "".join(lines)

    if print_immediately:
        print(f"\n✓ {name}: {elapsed*1000:.0f}ms")
        print(f"  {text}")

    return text, elapsed, name


def transcribe_coreml(audio_path: str, frames: int, itn: bool = False, print_immediately: bool = True) -> tuple[str, float, str]:
    """Transcribe using CoreML."""
    suffix = "+ITN" if itn else ""
    name = f"CoreML-{frames}{suffix} (ANE)"

    model = get_coreml_model(frames, itn=itn)
    text, elapsed = model.transcribe(audio_path)

    if print_immediately:
        print(f"\n✓ {name}: {elapsed*1000:.0f}ms")
        print(f"  {text}")

    return text, elapsed, name


def get_audio_duration(audio_path: str) -> float:
    """Get audio duration in seconds."""
    result = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", audio_path],
        capture_output=True,
        text=True
    )
    return float(result.stdout.strip())


def compare_file(audio_path: str):
    """Compare all backends on a single file, showing output immediately."""
    duration = get_audio_duration(audio_path)

    print(f"\n{'='*60}")
    print(f"Comparing: {audio_path}")
    print(f"Duration: {duration:.1f}s")
    print(f"{'='*60}")
    print("\nRunning all models (output shown as each completes)...")

    results = []

    # Run models sequentially to see speed difference clearly
    # (CoreML models can't run truly in parallel on same ANE anyway)

    # 1. CoreML-250 (fastest expected)
    text, elapsed, name = transcribe_coreml(audio_path, 250)
    results.append((name, elapsed, text, duration))

    # 2. CoreML-500
    text, elapsed, name = transcribe_coreml(audio_path, 500)
    results.append((name, elapsed, text, duration))

    # 3. CoreML-250+ITN (with punctuation)
    text, elapsed, name = transcribe_coreml(audio_path, 250, itn=True)
    results.append((name, elapsed, text, duration))

    # 4. CoreML-500+ITN (with punctuation)
    text, elapsed, name = transcribe_coreml(audio_path, 500, itn=True)
    results.append((name, elapsed, text, duration))

    # 5. Metal (slowest expected)
    text, elapsed, name = transcribe_metal(audio_path)
    results.append((name, elapsed, text, duration))

    # Summary
    print(f"\n{'='*60}")
    print("SUMMARY")
    print(f"{'='*60}")
    print(f"\n{'Model':<22} {'Time':>10} {'Speed':>12}")
    print("-" * 47)

    for name, elapsed, text, dur in results:
        speed = f"{dur/elapsed:.0f}x real-time"
        print(f"{name:<22} {elapsed*1000:>7.0f}ms {speed:>12}")


def load_models():
    """Pre-load CoreML models."""
    print("Loading models...")
    print("\n1. CoreML-250:")
    get_coreml_model(250)
    print("\n2. CoreML-500:")
    get_coreml_model(500)
    print("\n3. CoreML-250+ITN:")
    get_coreml_model(250, itn=True)
    print("\n4. CoreML-500+ITN:")
    get_coreml_model(500, itn=True)
    print("\n5. Metal: (loads per-request)")
    print("\nAll models ready!")


# Interactive mode functions
def start_recording():
    """Start recording with sox."""
    global recording_process, audio_file, is_recording

    if is_recording:
        return

    is_recording = True
    audio_file = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
    audio_file.close()

    print("\n🎤 Recording...")
    recording_process = subprocess.Popen(
        ["rec", "-q", "-c", "1", "-r", "16000", audio_file.name],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
    )


def stop_recording_and_compare():
    """Stop recording and compare all backends."""
    global recording_process, audio_file, is_recording

    if not is_recording:
        return

    is_recording = False

    # Stop recording
    if recording_process:
        recording_process.terminate()
        recording_process.wait()
        recording_process = None

    print("⏹️  Stopped. Transcribing...")

    # Compare
    if audio_file and os.path.exists(audio_file.name):
        compare_file(audio_file.name)

        # Cleanup
        os.unlink(audio_file.name)
        audio_file = None


def main():
    parser = argparse.ArgumentParser(description="Compare SenseVoice: Metal vs CoreML-250 vs CoreML-500")
    parser.add_argument("audio", nargs="?", help="Audio file to test (optional)")
    args = parser.parse_args()

    # Check sensevoice.cpp is installed
    if not SENSEVOICE_CPP.exists():
        print(f"Error: sensevoice.cpp not found at {SENSEVOICE_CPP}")
        print("Install with: cd voice && git clone https://github.com/lovemefan/SenseVoice.cpp sensevoice-cpp")
        sys.exit(1)

    if not SENSEVOICE_MODEL.exists():
        print(f"Error: Model not found at {SENSEVOICE_MODEL}")
        print("Download from: https://huggingface.co/lovemefan/sense-voice-gguf")
        sys.exit(1)

    print("=" * 60)
    print("SenseVoice Comparison")
    print("CoreML (250/500, ±ITN) vs Metal")
    print("=" * 60)

    load_models()

    if args.audio:
        # Single file comparison
        compare_file(args.audio)
    else:
        # Interactive mode
        from pynput import keyboard

        def on_press(key):
            if key == keyboard.Key.alt or key == keyboard.Key.alt_l or key == keyboard.Key.alt_r:
                start_recording()
            elif key == keyboard.Key.esc:
                print("\nExiting...")
                return False

        def on_release(key):
            if key == keyboard.Key.alt or key == keyboard.Key.alt_l or key == keyboard.Key.alt_r:
                stop_recording_and_compare()

        print("\n" + "-" * 60)
        print("Interactive Mode")
        print("-" * 60)
        print("  Hold [Option] -> Record")
        print("  Release       -> Compare all 3 backends")
        print("  [Esc]         -> Quit")
        print("\nHold Option key to start recording...\n")

        with keyboard.Listener(on_press=on_press, on_release=on_release) as listener:
            listener.join()


if __name__ == "__main__":
    main()
