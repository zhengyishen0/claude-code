#!/usr/bin/env python3
"""
Convert x-vector speaker embedding model from PyTorch to CoreML.

This script:
1. Loads the SpeechBrain x-vector model
2. Traces it with dummy input
3. Converts to CoreML using coremltools
4. Benchmarks PyTorch vs CoreML speed
5. Verifies output consistency

Usage:
    python convert_xvector_coreml.py
"""

import torch
import numpy as np
import time
from pathlib import Path

# Suppress warnings
import warnings
warnings.filterwarnings('ignore')


def load_xvector_model():
    """Load SpeechBrain x-vector model."""
    print("Loading SpeechBrain x-vector model...")

    from speechbrain.inference.speaker import EncoderClassifier

    model = EncoderClassifier.from_hparams(
        source="speechbrain/spkrec-xvect-voxceleb",
        savedir=Path.home() / ".cache" / "speechbrain" / "speechbrain-spkrec-xvect-voxceleb",
        run_opts={"device": "cpu"}
    )

    print("  Model loaded successfully")
    return model


def extract_embedding_module(model):
    """Extract the embedding module for tracing."""
    # The EncoderClassifier wraps the actual embedding model
    # We need to access the underlying modules

    # Get the embedding model
    embedding_model = model.mods.embedding_model

    return embedding_model


def trace_model(embedding_model, sample_rate=16000, duration=3.0):
    """Trace the model with dummy input."""
    print("Tracing model...")

    # Create dummy audio input (batch, time)
    num_samples = int(sample_rate * duration)
    dummy_input = torch.randn(1, num_samples)

    # Need to also trace the feature extraction
    # SpeechBrain x-vector expects mel features, not raw audio

    # Get the compute_features method
    # Actually, let's trace the full encode_batch pipeline

    print(f"  Input shape: {dummy_input.shape}")

    # Test forward pass
    with torch.no_grad():
        # The embedding model expects features, not raw audio
        # We need to understand the preprocessing pipeline
        pass

    return dummy_input


def convert_to_coreml(model, output_path):
    """Convert traced model to CoreML."""
    print("Converting to CoreML...")

    import coremltools as ct

    # For SpeechBrain, we need to trace the feature extraction + embedding
    # This is tricky because SpeechBrain uses a modular architecture

    # Let's try a different approach: create a wrapper module
    class XVectorWrapper(torch.nn.Module):
        def __init__(self, speechbrain_model):
            super().__init__()
            self.model = speechbrain_model

        def forward(self, audio):
            # audio: (batch, time) at 16kHz
            embeddings = self.model.encode_batch(audio)
            return embeddings

    wrapper = XVectorWrapper(model)
    wrapper.eval()

    # Create example input
    example_input = torch.randn(1, 48000)  # 3 seconds at 16kHz

    # Trace the model
    print("  Tracing with TorchScript...")
    try:
        traced = torch.jit.trace(wrapper, example_input)
    except Exception as e:
        print(f"  TorchScript tracing failed: {e}")
        print("  Trying torch.jit.script instead...")
        try:
            traced = torch.jit.script(wrapper)
        except Exception as e2:
            print(f"  Scripting also failed: {e2}")
            return None

    # Convert to CoreML
    print("  Converting traced model to CoreML...")
    try:
        mlmodel = ct.convert(
            traced,
            inputs=[ct.TensorType(name="audio", shape=(1, 48000))],
            outputs=[ct.TensorType(name="embedding")],
            compute_units=ct.ComputeUnit.ALL,
            minimum_deployment_target=ct.target.macOS14
        )

        # Save the model
        mlmodel.save(str(output_path))
        print(f"  Saved to: {output_path}")

        return mlmodel

    except Exception as e:
        print(f"  CoreML conversion failed: {e}")
        return None


def benchmark_pytorch(model, num_runs=20):
    """Benchmark PyTorch inference speed."""
    print(f"\nBenchmarking PyTorch ({num_runs} runs)...")

    # Create test audio (3 seconds)
    audio = torch.randn(1, 48000)

    # Warmup
    for _ in range(3):
        with torch.no_grad():
            _ = model.encode_batch(audio)

    # Benchmark
    times = []
    for _ in range(num_runs):
        start = time.perf_counter()
        with torch.no_grad():
            embedding = model.encode_batch(audio)
        elapsed = (time.perf_counter() - start) * 1000
        times.append(elapsed)

    avg_time = np.mean(times)
    std_time = np.std(times)

    print(f"  Average: {avg_time:.2f}ms ± {std_time:.2f}ms")
    print(f"  Embedding shape: {embedding.shape}")

    return avg_time, embedding.squeeze().numpy()


def benchmark_coreml(model_path, num_runs=20):
    """Benchmark CoreML inference speed."""
    print(f"\nBenchmarking CoreML ({num_runs} runs)...")

    import coremltools as ct

    # Load compiled model if available
    compiled_path = model_path.with_suffix('.mlmodelc')
    if compiled_path.exists():
        print(f"  Using compiled model: {compiled_path}")
        model = ct.models.CompiledMLModel(str(compiled_path), compute_units=ct.ComputeUnit.ALL)
    else:
        print(f"  Using package: {model_path}")
        model = ct.models.MLModel(str(model_path), compute_units=ct.ComputeUnit.ALL)

    # Create test audio
    audio = np.random.randn(1, 48000).astype(np.float32)

    # Warmup
    for _ in range(3):
        _ = model.predict({"audio": audio})

    # Benchmark
    times = []
    for _ in range(num_runs):
        start = time.perf_counter()
        result = model.predict({"audio": audio})
        elapsed = (time.perf_counter() - start) * 1000
        times.append(elapsed)

    avg_time = np.mean(times)
    std_time = np.std(times)

    embedding = result["embedding"]
    print(f"  Average: {avg_time:.2f}ms ± {std_time:.2f}ms")
    print(f"  Embedding shape: {embedding.shape}")

    return avg_time, embedding.squeeze()


def compile_coreml(model_path):
    """Compile CoreML model for faster loading using xcrun."""
    print("\nCompiling CoreML model...")

    import subprocess

    compiled_path = model_path.with_suffix('.mlmodelc')

    # Use xcrun coremlcompiler to compile
    try:
        result = subprocess.run([
            'xcrun', 'coremlcompiler', 'compile',
            str(model_path),
            str(model_path.parent)
        ], capture_output=True, text=True, check=True)

        print(f"  Compiled to: {compiled_path}")
        return compiled_path
    except subprocess.CalledProcessError as e:
        print(f"  Compilation failed: {e.stderr}")
        return None
    except FileNotFoundError:
        print("  xcrun not found - skipping compilation")
        return None


def main():
    output_dir = Path(__file__).parent / "models"
    output_dir.mkdir(exist_ok=True)

    output_path = output_dir / "xvector.mlpackage"

    # Load model
    model = load_xvector_model()

    # Benchmark PyTorch first
    pytorch_time, pytorch_embedding = benchmark_pytorch(model)

    # Convert to CoreML
    mlmodel = convert_to_coreml(model, output_path)

    if mlmodel is not None:
        # Compile for faster loading
        compile_coreml(output_path)

        # Benchmark CoreML
        coreml_time, coreml_embedding = benchmark_coreml(output_path)

        # Compare results
        print("\n" + "="*50)
        print("RESULTS")
        print("="*50)
        print(f"PyTorch:  {pytorch_time:.2f}ms")
        print(f"CoreML:   {coreml_time:.2f}ms")
        print(f"Speedup:  {pytorch_time/coreml_time:.2f}x")

        # Check embedding similarity
        similarity = np.dot(pytorch_embedding, coreml_embedding) / (
            np.linalg.norm(pytorch_embedding) * np.linalg.norm(coreml_embedding)
        )
        print(f"Embedding cosine similarity: {similarity:.4f}")

        if similarity > 0.99:
            print("✅ Embeddings match!")
        else:
            print("⚠️ Embeddings differ - check conversion")
    else:
        print("\n" + "="*50)
        print("CoreML conversion failed.")
        print("PyTorch baseline: {:.2f}ms".format(pytorch_time))
        print("="*50)


if __name__ == "__main__":
    main()
