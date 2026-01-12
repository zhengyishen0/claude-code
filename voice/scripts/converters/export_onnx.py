#!/usr/bin/env python3
"""
Export models to ONNX format for KMP pipeline
"""

import os
import sys
import torch
import numpy as np
from pathlib import Path

# Add voice directory to path
VOICE_DIR = Path(__file__).parent.parent.parent
sys.path.insert(0, str(VOICE_DIR / "pipelines" / "python"))

MODELS_DIR = VOICE_DIR / "models" / "onnx"


def export_xvector():
    """Export SpeechBrain xvector model to ONNX"""
    print("Exporting xvector to ONNX...")

    from speechbrain.inference.speaker import EncoderClassifier

    # Load the model
    classifier = EncoderClassifier.from_hparams(
        source="speechbrain/spkrec-xvect-voxceleb",
        savedir="pretrained_models/spkrec-xvect-voxceleb"
    )

    # Get the embedding model
    model = classifier.mods["embedding_model"]
    model.eval()

    # Create dummy input (3 seconds at 16kHz)
    dummy_input = torch.randn(1, 48000)

    # Export to ONNX
    output_path = MODELS_DIR / "xvector.onnx"

    torch.onnx.export(
        model,
        dummy_input,
        str(output_path),
        input_names=["audio"],
        output_names=["embedding"],
        dynamic_axes={
            "audio": {0: "batch", 1: "samples"},
            "embedding": {0: "batch"}
        },
        opset_version=14,
        do_constant_folding=True
    )

    print(f"  Saved to {output_path}")
    print(f"  Size: {output_path.stat().st_size / 1024 / 1024:.2f} MB")

    # Verify
    import onnxruntime as ort
    session = ort.InferenceSession(str(output_path))
    test_input = np.random.randn(1, 48000).astype(np.float32)
    result = session.run(None, {"audio": test_input})
    print(f"  Output shape: {result[0].shape}")


def export_sensevoice():
    """Export SenseVoice model to ONNX"""
    print("Exporting SenseVoice to ONNX...")

    # SenseVoice uses a custom architecture, need to load from checkpoint
    model_path = VOICE_DIR / "transcription" / "pytorch" / "model.pt"

    if not model_path.exists():
        print(f"  Error: Model not found at {model_path}")
        print("  Trying alternative: using funasr export...")
        export_sensevoice_funasr()
        return

    # Load model
    model = torch.jit.load(str(model_path))
    model.eval()

    # Create dummy input matching LFR-transformed mel spectrogram
    # Input shape: (batch, frames, features) = (1, 500, 560)
    dummy_input = torch.randn(1, 500, 560)

    output_path = MODELS_DIR / "sensevoice.onnx"

    torch.onnx.export(
        model,
        dummy_input,
        str(output_path),
        input_names=["mel_lfr"],
        output_names=["logits"],
        dynamic_axes={
            "mel_lfr": {0: "batch", 1: "frames"},
            "logits": {0: "batch", 1: "frames"}
        },
        opset_version=14,
        do_constant_folding=True
    )

    print(f"  Saved to {output_path}")
    print(f"  Size: {output_path.stat().st_size / 1024 / 1024:.2f} MB")


def export_sensevoice_funasr():
    """Export SenseVoice using FunASR's export functionality"""
    try:
        from funasr import AutoModel
        from funasr.utils.export_utils import export_onnx

        print("  Loading SenseVoice model from FunASR...")
        model = AutoModel(model="iic/SenseVoiceSmall")

        output_path = MODELS_DIR / "sensevoice.onnx"

        # Export using FunASR utility
        export_onnx(model, str(output_path))

        print(f"  Saved to {output_path}")

    except ImportError:
        print("  FunASR not installed. Please install: pip install funasr")
    except Exception as e:
        print(f"  Error: {e}")
        print("  Trying manual ONNX export...")
        export_sensevoice_manual()


def export_sensevoice_manual():
    """Manual export of SenseVoice encoder to ONNX"""
    print("  Attempting manual SenseVoice export...")

    try:
        # Check if we have a TorchScript model
        model_path = VOICE_DIR / "transcription" / "pytorch" / "model.pt"

        if model_path.exists():
            print(f"  Loading from {model_path}")
            model = torch.jit.load(str(model_path), map_location='cpu')
            model.eval()

            # Dummy input: LFR-transformed mel (batch, frames, features)
            dummy_input = torch.randn(1, 500, 560)

            output_path = MODELS_DIR / "sensevoice.onnx"

            with torch.no_grad():
                torch.onnx.export(
                    model,
                    dummy_input,
                    str(output_path),
                    input_names=["input"],
                    output_names=["output"],
                    opset_version=14,
                    do_constant_folding=True
                )

            print(f"  Saved to {output_path}")
            print(f"  Size: {output_path.stat().st_size / 1024 / 1024:.2f} MB")
        else:
            print(f"  Model not found at {model_path}")

    except Exception as e:
        print(f"  Failed: {e}")


def main():
    os.makedirs(MODELS_DIR, exist_ok=True)

    print(f"Output directory: {MODELS_DIR}")
    print()

    # Export xvector
    try:
        export_xvector()
    except Exception as e:
        print(f"  xvector export failed: {e}")

    print()

    # Export SenseVoice
    try:
        export_sensevoice()
    except Exception as e:
        print(f"  SenseVoice export failed: {e}")

    print()
    print("Done!")
    print()
    print("Models in output directory:")
    for f in MODELS_DIR.glob("*.onnx"):
        print(f"  {f.name}: {f.stat().st_size / 1024 / 1024:.2f} MB")


if __name__ == "__main__":
    main()
