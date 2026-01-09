#!/usr/bin/env python3
"""
Build CoreML models from PyTorch SenseVoice.

Usage:
    python build_models.py [--frames N [N ...]]

Examples:
    python build_models.py                    # Build all (150, 250, 500, 750, 1000, 1500, 2000)
    python build_models.py --frames 250       # Build only 250
    python build_models.py --frames 250 500   # Build 250 and 500
"""

import torch
import torch.nn as nn
import coremltools as ct
import numpy as np
import time
import sys
import os
import argparse
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
PYTORCH_DIR = SCRIPT_DIR / "pytorch"
MODELS_DIR = SCRIPT_DIR / "models"


class SenseVoiceEncoderWrapper(nn.Module):
    """Wrapper for CoreML-compatible encoder."""

    def __init__(self, encoder, ctc):
        super().__init__()
        self.encoder = encoder
        self.ctc = ctc

    def forward(self, x):
        batch_size, time_steps, _ = x.shape
        ilens = torch.tensor([time_steps] * batch_size, dtype=torch.long)
        encoder_out, _ = self.encoder(x, ilens)
        logits = self.ctc.ctc_lo(encoder_out)
        return logits


def build_model(wrapper, n_frames: int) -> None:
    """Build CoreML model with specified frame count."""
    output_path = MODELS_DIR / f"sensevoice-{n_frames}.mlpackage"
    max_seconds = n_frames * 0.06

    if output_path.exists():
        print(f"  [{n_frames} frames ({max_seconds:.0f}s)] Already exists, skipping...")
        return

    print(f"  [{n_frames} frames ({max_seconds:.0f}s)] Building...")

    dummy = torch.randn(1, n_frames, 560)
    with torch.no_grad():
        traced = torch.jit.trace(wrapper, dummy)

    start = time.time()
    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(shape=(1, n_frames, 560), name="audio_features", dtype=np.float32)],
        outputs=[ct.TensorType(name="logits", dtype=np.float32)],
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.macOS13,
        compute_precision=ct.precision.FLOAT16
    )
    mlmodel.save(str(output_path))
    print(f"    Saved in {time.time() - start:.1f}s")


def main():
    parser = argparse.ArgumentParser(description="Build CoreML models from PyTorch")
    parser.add_argument("--frames", type=int, nargs="+",
                       default=[150, 250, 500, 750, 1000, 1500, 2000],
                       help="Frame counts to build. Default: all")
    args = parser.parse_args()

    print("=" * 60)
    print("Building SenseVoice CoreML Models")
    print("=" * 60)

    # Check PyTorch model exists
    if not PYTORCH_DIR.exists():
        print(f"\nError: PyTorch model not found at {PYTORCH_DIR}")
        print("Download it first:")
        print("  git lfs install")
        print("  git clone https://huggingface.co/FunAudioLLM/SenseVoiceSmall pytorch/")
        sys.exit(1)

    # Create models directory
    MODELS_DIR.mkdir(exist_ok=True)

    # Load PyTorch model
    print("\nLoading PyTorch model...")
    sys.path.insert(0, str(PYTORCH_DIR))

    from funasr import AutoModel
    model = AutoModel(
        model=str(PYTORCH_DIR),
        trust_remote_code=True,
        device="cpu",
        disable_update=True
    )
    inner_model = model.model
    inner_model.eval()

    # Create wrapper
    wrapper = SenseVoiceEncoderWrapper(inner_model.encoder, inner_model.ctc)
    wrapper.eval()

    # Build models
    print(f"\nBuilding {len(args.frames)} model(s)...")
    for n_frames in args.frames:
        build_model(wrapper, n_frames)

    print("\nDone!")
    print(f"Models saved to: {MODELS_DIR}")


if __name__ == "__main__":
    main()
