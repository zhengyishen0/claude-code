#!/usr/bin/env python3
"""
x-vector PyTorch to CoreML Conversion Script

This script converts the SpeechBrain x-vector speaker embedding model
from PyTorch to CoreML format for native Apple Silicon acceleration.

x-vector: 512-dim speaker embeddings, ~15ms for 5s audio
Benchmark: PyTorch vs CoreML speed comparison

Usage:
    python convert_xvector_to_coreml.py
"""

import sys
import torch
import numpy as np
import coremltools as ct
from pathlib import Path
import time
from typing import Tuple

# Configuration
SCRIPT_DIR = Path(__file__).parent
OUTPUT_DIR = SCRIPT_DIR / "voice" / "speaker_id" / "models"
OUTPUT_PATH = OUTPUT_DIR / "xvector_speaker_embedding.mlpackage"

# Fixed input for conversion: 5 seconds at 16kHz = 80000 samples
FIXED_INPUT_LENGTH = 80000


class XVectorWrapper(torch.nn.Module):
    """
    Wrapper around SpeechBrain x-vector embedding encoder for CoreML conversion.

    Simplifies the model interface to accept (batch, samples) and output (batch, embedding).
    """

    def __init__(self, classifier):
        super().__init__()
        # Store classifier for encoding
        self.classifier = classifier

    def forward(self, waveform: torch.Tensor) -> torch.Tensor:
        """
        Extract x-vector embedding from waveform.

        Args:
            waveform: (1, num_samples) - mono audio at 16kHz

        Returns:
            embedding: (512,) - speaker embedding (normalized)
        """
        # Ensure shape is (batch, samples)
        if waveform.dim() == 1:
            waveform = waveform.unsqueeze(0)

        # Extract embedding using classifier's encode_batch method
        # This handles normalization and everything internally
        embeddings = self.classifier.encode_batch(waveform)  # Output: (batch, 512)

        # Return single embedding (remove batch dimension if present)
        if embeddings.dim() > 1:
            return embeddings.squeeze(0)  # Return (512,)
        return embeddings


def load_xvector_model():
    """Load pre-trained x-vector model from SpeechBrain."""
    print("Loading x-vector model from SpeechBrain...")

    try:
        from speechbrain.inference.speaker import SpeakerRecognition

        classifier = SpeakerRecognition.from_hparams(
            source="speechbrain/spkrec-xvect-voxceleb",
            savedir="pretrained_models/spkrec-xvect-voxceleb",
            run_opts={"device": "cpu"}
        )

        # Return the full classifier (we'll extract embeddings using its method)
        return classifier

    except ImportError:
        print("ERROR: SpeechBrain not installed")
        print("Install with: pip install speechbrain")
        sys.exit(1)


def convert_to_coreml(embedding_model) -> str:
    """
    Convert x-vector embedding model to CoreML.

    Args:
        embedding_model: Loaded PyTorch x-vector model

    Returns:
        path to generated .mlpackage
    """
    print(f"\nConverting x-vector to CoreML...")
    print(f"Input: (1, {FIXED_INPUT_LENGTH}) - mono audio at 16kHz")
    print(f"Output: (512,) - speaker embedding")

    # Create wrapper
    wrapper = XVectorWrapper(embedding_model)
    wrapper.eval()

    # Create example input
    example_input = torch.randn(1, FIXED_INPUT_LENGTH)

    try:
        # Trace the model
        print("Tracing model...")
        traced_model = torch.jit.trace(wrapper, example_input)

        # Convert to CoreML
        print("Converting to CoreML...")
        mlmodel = ct.convert(
            traced_model,
            inputs=[ct.TensorType(shape=(1, FIXED_INPUT_LENGTH), name="waveform")],
            outputs=[ct.TensorType(name="embedding")],
            compute_units=ct.ComputeUnit.CPU_AND_NE,  # Use Neural Engine
            minimum_deployment_target=ct.target.iOS14
        )

        # Set model properties
        mlmodel.author = "YouPu"
        mlmodel.short_description = "x-vector speaker embedding (512-dim)"
        mlmodel.input_description["waveform"] = "Mono audio waveform at 16kHz"
        mlmodel.output_description["embedding"] = "512-dimensional speaker embedding"

        # Save
        OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
        mlmodel.save(str(OUTPUT_PATH))

        print(f"✅ Conversion successful!")
        print(f"📦 Saved to: {OUTPUT_PATH}")

        return str(OUTPUT_PATH)

    except Exception as e:
        print(f"❌ Conversion failed: {e}")
        sys.exit(1)


def benchmark_models(classifier, mlmodel_path: str):
    """
    Benchmark PyTorch vs CoreML inference speed.

    Args:
        classifier: Original SpeechBrain classifier
        mlmodel_path: Path to converted CoreML model
    """
    print(f"\n{'='*60}")
    print("BENCHMARKING: PyTorch vs CoreML")
    print(f"{'='*60}")

    import coremltools

    # Load CoreML model
    print("Loading CoreML model...")
    mlmodel = coremltools.models.MLModel(mlmodel_path)

    # Test audio (5 seconds at 16kHz = 80000 samples)
    test_audio = np.random.randn(FIXED_INPUT_LENGTH).astype(np.float32)

    num_iterations = 10

    # Benchmark PyTorch
    print(f"\n🔵 PyTorch x-vector (CPU):")
    with torch.no_grad():
        # Warmup
        warmup = torch.randn(1, FIXED_INPUT_LENGTH)
        _ = classifier.encode_batch(warmup)

        times = []
        for _ in range(num_iterations):
            start = time.time()
            input_tensor = torch.from_numpy(test_audio).unsqueeze(0)
            output = classifier.encode_batch(input_tensor)
            elapsed = (time.time() - start) * 1000  # milliseconds
            times.append(elapsed)

    pytorch_avg = np.mean(times)
    pytorch_std = np.std(times)
    print(f"  Average: {pytorch_avg:.2f} ± {pytorch_std:.2f} ms")
    print(f"  Min: {np.min(times):.2f} ms, Max: {np.max(times):.2f} ms")

    # Benchmark CoreML
    print(f"\n🟢 CoreML x-vector (Neural Engine):")
    try:
        times = []
        for _ in range(num_iterations):
            start = time.time()
            output = mlmodel.predict({"waveform": test_audio.reshape(1, -1)})
            elapsed = (time.time() - start) * 1000
            times.append(elapsed)

        coreml_avg = np.mean(times)
        coreml_std = np.std(times)
        print(f"  Average: {coreml_avg:.2f} ± {coreml_std:.2f} ms")
        print(f"  Min: {np.min(times):.2f} ms, Max: {np.max(times):.2f} ms")

        # Comparison
        speedup = pytorch_avg / coreml_avg
        improvement = ((pytorch_avg - coreml_avg) / pytorch_avg) * 100

        print(f"\n📊 COMPARISON:")
        print(f"  CoreML is {speedup:.1f}x faster")
        print(f"  Improvement: {improvement:+.1f}%")

    except Exception as e:
        print(f"  ❌ CoreML inference failed: {e}")


def main():
    print("🎤 x-vector Speaker Embedding Conversion")
    print("=" * 60)

    # Load model
    classifier = load_xvector_model()

    # Convert to CoreML
    mlmodel_path = convert_to_coreml(classifier)

    # Benchmark
    benchmark_models(classifier, mlmodel_path)

    print("\n✅ Conversion complete!")
    print(f"Use this in Swift by adding the .mlmodelc bundle to Xcode")


if __name__ == "__main__":
    main()
