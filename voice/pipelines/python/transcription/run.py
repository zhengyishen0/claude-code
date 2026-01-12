#!/usr/bin/env python3
"""
Voice input with Option key hold-to-record.

Usage:
    python run.py [--frames N]

Hold Option key to record, release to transcribe.
Press Escape to quit.

Options:
    --frames N   Frame count (150, 250, 500, etc). Default: 250
"""

import subprocess
import tempfile
import time
import os
import argparse
from pathlib import Path

from pynput import keyboard

# Paths
SCRIPT_DIR = Path(__file__).parent

# Global state
recording_process = None
audio_file = None
is_recording = False
model = None


def load_model(frames: int, compiled: bool = True, itn: bool = True):
    """Load the transcription model."""
    global model
    from sensevoice_coreml import SenseVoiceCoreML
    model = SenseVoiceCoreML(frames=frames, compiled=compiled, itn=itn)


def start_recording():
    """Start recording with sox."""
    global recording_process, audio_file, is_recording

    if is_recording:
        return

    is_recording = True
    audio_file = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
    audio_file.close()

    print("Recording...")
    recording_process = subprocess.Popen(
        ["rec", "-q", "-c", "1", "-r", "16000", audio_file.name],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
    )


def stop_recording_and_transcribe():
    """Stop recording and transcribe."""
    global recording_process, audio_file, is_recording

    if not is_recording:
        return

    is_recording = False

    # Stop recording
    if recording_process:
        recording_process.terminate()
        recording_process.wait()
        recording_process = None

    print("Transcribing...")

    # Transcribe
    if audio_file and os.path.exists(audio_file.name):
        transcript, elapsed = model.transcribe(audio_file.name)

        print(f"\n[{elapsed*1000:.0f}ms] {transcript}\n")

        # Cleanup
        os.unlink(audio_file.name)
        audio_file = None


def on_press(key):
    """Handle key press."""
    if key == keyboard.Key.alt or key == keyboard.Key.alt_l or key == keyboard.Key.alt_r:
        start_recording()
    elif key == keyboard.Key.esc:
        print("Exiting...")
        return False


def on_release(key):
    """Handle key release."""
    if key == keyboard.Key.alt or key == keyboard.Key.alt_l or key == keyboard.Key.alt_r:
        stop_recording_and_transcribe()


def main():
    parser = argparse.ArgumentParser(description="Voice input with hold-to-record")
    parser.add_argument("--frames", type=int, default=500,
                       help="Frame count (250 or 500). Default: 500")
    parser.add_argument("--no-compiled", action="store_true",
                       help="Use original .mlpackage instead of pre-compiled .mlmodelc")
    parser.add_argument("--no-itn", action="store_true",
                       help="Disable ITN (punctuation). Default: ITN enabled")
    args = parser.parse_args()

    print("=" * 50)
    print("Voice Input - SenseVoice CoreML")
    print("=" * 50)
    print()
    print("  Hold [Option] -> Record")
    print("  Release       -> Transcribe")
    print("  [Esc]         -> Quit")
    print()

    load_model(args.frames, compiled=not args.no_compiled, itn=not args.no_itn)

    print("\nReady! Hold Option key to start recording...\n")

    with keyboard.Listener(on_press=on_press, on_release=on_release) as listener:
        listener.join()


if __name__ == "__main__":
    main()
