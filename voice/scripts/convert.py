#!/usr/bin/env python3
"""
Unified model conversion CLI for voice pipeline.

Usage:
    python convert.py <model_type> [--format FORMAT] [options]

Model types:
    asr         - SenseVoice speech recognition
    speaker     - x-vector/ECAPA speaker embedding
    separation  - SepReformer speech separation
    vad         - Silero VAD (download only)
    all         - Convert all models

Formats:
    coreml      - Apple CoreML (default)
    onnx        - ONNX Runtime (cross-platform)

Examples:
    python convert.py asr
    python convert.py speaker --format onnx
    python convert.py all
"""

import argparse
import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
CONVERTERS_DIR = SCRIPT_DIR / "converters"
VOICE_DIR = SCRIPT_DIR.parent
MODELS_DIR = VOICE_DIR / "models"


def run_converter(script_name: str, args: list = None):
    """Run a converter script."""
    script_path = CONVERTERS_DIR / script_name
    if not script_path.exists():
        print(f"Error: Converter not found: {script_path}")
        return False

    cmd = [sys.executable, str(script_path)] + (args or [])
    print(f"\n{'='*60}")
    print(f"Running: {' '.join(cmd)}")
    print('='*60)

    result = subprocess.run(cmd, cwd=str(VOICE_DIR))
    return result.returncode == 0


def download_vad():
    """Download Silero VAD model."""
    import urllib.request

    onnx_dir = MODELS_DIR / "onnx"
    onnx_dir.mkdir(parents=True, exist_ok=True)

    vad_path = onnx_dir / "silero_vad.onnx"
    if vad_path.exists():
        print(f"VAD model exists: {vad_path}")
        return True

    url = "https://github.com/snakers4/silero-vad/raw/master/src/silero_vad/data/silero_vad.onnx"
    print(f"Downloading Silero VAD...")

    try:
        urllib.request.urlretrieve(url, vad_path)
        print(f"Downloaded to: {vad_path}")
        return True
    except Exception as e:
        print(f"Error: {e}")
        return False


def main():
    parser = argparse.ArgumentParser(description="Model conversion CLI")
    parser.add_argument("model_type", choices=["asr", "speaker", "separation", "vad", "all"])
    parser.add_argument("--format", "-f", choices=["coreml", "onnx"], default="coreml")
    parser.add_argument("--frames", type=int, default=500)
    parser.add_argument("--no-itn", action="store_true")

    args = parser.parse_args()
    success = True

    if args.model_type in ["asr", "all"]:
        converter_args = ["--frames", str(args.frames)]
        if not args.no_itn:
            converter_args.append("--itn")
        if args.format == "coreml":
            success &= run_converter("asr.py", converter_args)
        else:
            success &= run_converter("export_onnx.py", ["--asr"])

    if args.model_type in ["speaker", "all"]:
        if args.format == "coreml":
            success &= run_converter("speaker_id.py")
        else:
            success &= run_converter("export_onnx.py", ["--speaker"])

    if args.model_type in ["separation", "all"]:
        success &= run_converter("separation.py")

    if args.model_type in ["vad", "all"]:
        success &= download_vad()

    print("\n" + "="*60)
    print("Done!" if success else "Some conversions failed")
    print("="*60)

    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
