#!/usr/bin/env python3
"""
Build CoreML models from PyTorch SenseVoice.

Usage:
    python build_models.py [--frames N [N ...]] [--itn]

Examples:
    python build_models.py --frames 250 500           # Build 250 and 500 (no punctuation)
    python build_models.py --frames 250 500 --itn     # Build 250 and 500 with punctuation
"""

import torch
import torch.nn as nn
import coremltools as ct
import numpy as np
import time
import sys
import argparse
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
PYTORCH_DIR = SCRIPT_DIR / "pytorch"
MODELS_DIR = SCRIPT_DIR / "models"

# ITN embedding tokens (from SenseVoice model)
ITN_TOKEN = 14   # with punctuation
NO_ITN_TOKEN = 15  # without punctuation


class SenseVoiceEncoderWrapper(nn.Module):
    """Wrapper for CoreML-compatible encoder."""

    def __init__(self, encoder, ctc, embed, language_id: int = 0, use_itn: bool = False):
        super().__init__()
        self.encoder = encoder
        self.ctc = ctc
        self.embed = embed
        self.language_id = language_id
        self.use_itn = use_itn
        # Pre-compute embedding tokens: [language, 1, 2, itn_token]
        itn_token = ITN_TOKEN if use_itn else NO_ITN_TOKEN
        self.register_buffer('embedding_ids', torch.LongTensor([[language_id, 1, 2, itn_token]]))

    def forward(self, x):
        batch_size, time_steps, _ = x.shape

        # Get embeddings for language and ITN tokens
        embeddings = self.embed(self.embedding_ids)  # (1, 4, embed_dim)
        embeddings = embeddings.expand(batch_size, -1, -1)  # (batch, 4, embed_dim)

        # Prepend embeddings to audio features
        x = torch.cat([embeddings, x], dim=1)  # (batch, 4 + time_steps, embed_dim)

        ilens = torch.tensor([x.shape[1]] * batch_size, dtype=torch.long)
        encoder_out, _ = self.encoder(x, ilens)
        logits = self.ctc.ctc_lo(encoder_out)
        return logits


class SenseVoiceEncoderWrapperNoEmbed(nn.Module):
    """Wrapper without embeddings (original behavior)."""

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


def build_model(wrapper, n_frames: int, use_itn: bool, force: bool = False) -> None:
    """Build CoreML model with specified frame count."""
    suffix = "-itn" if use_itn else ""
    output_path = MODELS_DIR / f"sensevoice-{n_frames}{suffix}.mlpackage"
    max_seconds = n_frames * 0.06

    if output_path.exists() and not force:
        print(f"  [{n_frames} frames{suffix}] Already exists, skipping...")
        return

    print(f"  [{n_frames} frames{suffix} ({max_seconds:.0f}s)] Building...")

    # Input size is 560 (80 mels * 7 LFR frames)
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
    parser.add_argument("--frames", type=int, nargs="+", default=[250, 500],
                       help="Frame counts to build. Default: 250 500")
    parser.add_argument("--itn", action="store_true",
                       help="Enable ITN (punctuation). Creates models with -itn suffix.")
    parser.add_argument("--force", action="store_true",
                       help="Overwrite existing models")
    args = parser.parse_args()

    print("=" * 60)
    print("Building SenseVoice CoreML Models")
    print(f"ITN (punctuation): {'enabled' if args.itn else 'disabled'}")
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
    if args.itn:
        # With ITN: include embedding layer
        wrapper = SenseVoiceEncoderWrapper(
            inner_model.encoder,
            inner_model.ctc,
            inner_model.embed,
            language_id=0,  # 0 = auto-detect
            use_itn=True
        )
    else:
        # Without ITN: original behavior (no embeddings)
        wrapper = SenseVoiceEncoderWrapperNoEmbed(inner_model.encoder, inner_model.ctc)

    wrapper.eval()

    # Build models
    print(f"\nBuilding {len(args.frames)} model(s)...")
    for n_frames in args.frames:
        build_model(wrapper, n_frames, args.itn, args.force)

    print("\nDone!")
    print(f"Models saved to: {MODELS_DIR}")


if __name__ == "__main__":
    main()
