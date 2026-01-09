#!/usr/bin/env python3
"""
SepReformer PyTorch to CoreML Conversion Script

This script converts the SepReformer speech separation model from PyTorch to CoreML format.

Potential issues to handle:
1. torch.nn.functional.upsample (deprecated) -> interpolate
2. Dynamic tensor creation (torch.arange, torch.zeros)
3. Dynamic input shapes
4. In-place operations (clamp_)
"""

import sys
import os
import torch
import yaml
import coremltools as ct
from pathlib import Path

# Add the SepReformer path
SCRIPT_DIR = Path(__file__).parent
sys.path.insert(0, str(SCRIPT_DIR))

# Configuration
MODEL_NAME = "SepReformer_Base_WSJ0"
MODEL_DIR = SCRIPT_DIR / "models" / MODEL_NAME
WEIGHTS_PATH = MODEL_DIR / "log" / "scratch_weights" / "epoch.0180.pth"
CONFIG_PATH = MODEL_DIR / "configs.yaml"
OUTPUT_PATH = SCRIPT_DIR / "SepReformer_Base.mlpackage"

# Fixed input length for CoreML (in samples at 8kHz)
# 4 seconds = 32000 samples, but we'll use a round number divisible by 16 (stride) and 2^4 (num_stages)
FIXED_INPUT_LENGTH = 32000  # 4 seconds at 8kHz


def patch_ega_module(model, fixed_down_len):
    """
    Patch EGA modules to use fixed down_len instead of dynamic pos_k.shape[0].

    This is needed because torch.jit.trace cannot handle dynamic tensor shape access.
    """
    import types

    def make_patched_forward(original_module, down_len):
        """Create a patched forward that uses fixed down_len."""
        def patched_forward(self, x, pos_k):
            # Use fixed down_len instead of pos_k.shape[0]
            x_down = torch.nn.functional.adaptive_avg_pool1d(input=x, output_size=down_len)
            x = x.permute([0, 2, 1])
            x_down = x_down.permute([0, 2, 1])
            x_down = self.block['self_attn'](x_down, pos_k, None)
            x_down = x_down.permute([0, 2, 1])
            x_downup = torch.nn.functional.interpolate(input=x_down, size=x.shape[1], mode='nearest')
            x_downup = x_downup.permute([0, 2, 1])
            x = x + self.block['linear'](x) * x_downup
            return x
        return patched_forward

    # Patch all EGA modules in encoder stages
    for enc_stage in model.separator.enc_stages:
        enc_stage.g_block_1.block['ega'].forward = types.MethodType(
            make_patched_forward(enc_stage.g_block_1.block['ega'], fixed_down_len),
            enc_stage.g_block_1.block['ega']
        )
        enc_stage.g_block_2.block['ega'].forward = types.MethodType(
            make_patched_forward(enc_stage.g_block_2.block['ega'], fixed_down_len),
            enc_stage.g_block_2.block['ega']
        )

    # Patch bottleneck
    model.separator.bottleneck_G.g_block_1.block['ega'].forward = types.MethodType(
        make_patched_forward(model.separator.bottleneck_G.g_block_1.block['ega'], fixed_down_len),
        model.separator.bottleneck_G.g_block_1.block['ega']
    )
    model.separator.bottleneck_G.g_block_2.block['ega'].forward = types.MethodType(
        make_patched_forward(model.separator.bottleneck_G.g_block_2.block['ega'], fixed_down_len),
        model.separator.bottleneck_G.g_block_2.block['ega']
    )

    # Patch decoder stages
    for dec_stage in model.separator.dec_stages:
        dec_stage.g_block_1.block['ega'].forward = types.MethodType(
            make_patched_forward(dec_stage.g_block_1.block['ega'], fixed_down_len),
            dec_stage.g_block_1.block['ega']
        )
        dec_stage.g_block_2.block['ega'].forward = types.MethodType(
            make_patched_forward(dec_stage.g_block_2.block['ega'], fixed_down_len),
            dec_stage.g_block_2.block['ega']
        )
        dec_stage.g_block_3.block['ega'].forward = types.MethodType(
            make_patched_forward(dec_stage.g_block_3.block['ega'], fixed_down_len),
            dec_stage.g_block_3.block['ega']
        )

    return model


class SepReformerWrapper(torch.nn.Module):
    """
    Wrapper for SepReformer to make it CoreML-compatible.

    This is a simple wrapper that:
    1. Handles input shape normalization
    2. Calls the original model's forward
    3. Returns only the main outputs (not aux)
    4. Trims output to input length
    """

    def __init__(self, model, input_length=FIXED_INPUT_LENGTH):
        super().__init__()
        self.model = model
        self.input_length = input_length

    def forward(self, x):
        """
        Forward pass for CoreML.

        Args:
            x: Input audio tensor of shape [batch, samples]

        Returns:
            Tuple of separated audio tensors [speaker1, speaker2], each [batch, samples]
        """
        # Call original model forward
        # Returns: audio (list of 2 speakers), audio_aux (auxiliary outputs)
        audio, _ = self.model(x)

        # Get speaker outputs and trim to input length
        spk1 = audio[0][..., :self.input_length]
        spk2 = audio[1][..., :self.input_length]

        return spk1, spk2


def load_model(config_path, weights_path):
    """Load the SepReformer model with weights."""

    # Load config
    with open(config_path, 'r') as f:
        config = yaml.safe_load(f)

    model_config = config['config']['model']

    # Import model class - need to set up proper package structure
    import importlib.util

    # First, load the network module
    network_path = MODEL_DIR / "modules" / "network.py"
    spec = importlib.util.spec_from_file_location("network", network_path)
    network_module = importlib.util.module_from_spec(spec)
    sys.modules["network"] = network_module
    spec.loader.exec_module(network_module)

    # Load the module.py
    module_path = MODEL_DIR / "modules" / "module.py"
    spec = importlib.util.spec_from_file_location("module", module_path)
    module_module = importlib.util.module_from_spec(spec)
    sys.modules["module"] = module_module

    # Patch the module imports
    module_module.AudioEncoder = None
    module_module.FeatureProjector = None
    module_module.Separator = None
    module_module.OutputLayer = None
    module_module.AudioDecoder = None

    # Load module.py with patched network
    exec(open(module_path).read().replace("from .network import *", "from network import *").replace("from utils.decorators import *", ""), module_module.__dict__)

    # Now load model.py
    model_path = MODEL_DIR / "model.py"
    model_code = open(model_path).read()
    model_code = model_code.replace("from .modules.module import *", "from module import *")
    model_code = model_code.replace("from utils.decorators import *", "")
    model_code = model_code.replace("@logger_wraps()", "")

    model_namespace = {"torch": torch, "warnings": __import__("warnings")}
    model_namespace.update(module_module.__dict__)
    exec(model_code, model_namespace)

    Model = model_namespace["Model"]

    # Create model
    model = Model(**model_config)

    # Load weights - checkpoint may have nested structure
    checkpoint = torch.load(weights_path, map_location='cpu')
    if 'model_state_dict' in checkpoint:
        state_dict = checkpoint['model_state_dict']
    elif 'state_dict' in checkpoint:
        state_dict = checkpoint['state_dict']
    else:
        state_dict = checkpoint
    model.load_state_dict(state_dict)
    model.eval()

    print(f"Loaded model from {weights_path}")
    print(f"Model parameters: {sum(p.numel() for p in model.parameters()):,}")

    return model, model_config


def convert_to_coreml(model, input_length=FIXED_INPUT_LENGTH):
    """Convert PyTorch model to CoreML via direct tracing."""
    import numpy as np

    print(f"\nConverting to CoreML with fixed input length: {input_length} samples ({input_length/8000:.2f}s)")

    # Calculate fixed down_len for EGA modules
    # For 32000 samples at 8kHz:
    # - After encoder (stride=4): 8000 frames
    # - After 4 downsampling stages (2^4=16): 500 frames
    encoder_len = input_length // 4
    fixed_down_len = encoder_len // (2 ** 4)  # num_stages = 4
    print(f"  Fixed down_len for EGA: {fixed_down_len}")

    # Patch EGA modules to use fixed sizes
    print("Patching EGA modules for fixed sizes...")
    model = patch_ega_module(model, fixed_down_len)

    # Wrap model for CoreML compatibility
    wrapper = SepReformerWrapper(model, input_length=input_length)
    wrapper.eval()

    # First test that the model works with PyTorch
    print("Testing PyTorch model...")
    with torch.no_grad():
        test_input = torch.randn(1, input_length)
        test_out1, test_out2 = wrapper(test_input)
        print(f"  PyTorch output shapes: speaker1={test_out1.shape}, speaker2={test_out2.shape}")

    # Create example input
    example_input = torch.randn(1, input_length)

    # Trace the model
    print("Tracing model with TorchScript...")
    with torch.no_grad():
        traced = torch.jit.trace(wrapper, example_input)
    print("  Tracing successful!")

    # Test traced model
    print("Testing traced model...")
    with torch.no_grad():
        out1, out2 = traced(example_input)
        print(f"  Traced output shapes: speaker1={out1.shape}, speaker2={out2.shape}")

    # Convert to CoreML
    print("Converting to CoreML (this may take a few minutes)...")
    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.TensorType(
                shape=(1, input_length),
                name="audio_input",
                dtype=np.float32
            )
        ],
        outputs=[
            ct.TensorType(name="speaker1", dtype=np.float32),
            ct.TensorType(name="speaker2", dtype=np.float32)
        ],
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.macOS14,
        compute_precision=ct.precision.FLOAT32,  # Keep FP32 for accuracy
    )

    # Add metadata
    mlmodel.author = "SepReformer (NeurIPS 2024)"
    mlmodel.short_description = "Speech separation model - separates 2 speakers from mixed audio"

    return mlmodel


def main():
    print("=" * 60)
    print("SepReformer PyTorch to CoreML Conversion")
    print("=" * 60)

    # Check paths
    if not WEIGHTS_PATH.exists():
        print(f"ERROR: Weights not found at {WEIGHTS_PATH}")
        sys.exit(1)

    if not CONFIG_PATH.exists():
        print(f"ERROR: Config not found at {CONFIG_PATH}")
        sys.exit(1)

    # Load model
    print("\n1. Loading PyTorch model...")
    model, config = load_model(CONFIG_PATH, WEIGHTS_PATH)

    # Convert to CoreML
    print("\n2. Converting to CoreML...")
    try:
        mlmodel = convert_to_coreml(model, FIXED_INPUT_LENGTH)

        # Save
        print(f"\n3. Saving to {OUTPUT_PATH}...")
        mlmodel.save(str(OUTPUT_PATH))
        print(f"SUCCESS! Model saved to {OUTPUT_PATH}")

        # Print model info
        print("\nModel Info:")
        print(f"  Input: audio_input - shape (1, {FIXED_INPUT_LENGTH})")
        print(f"  Outputs: speaker1, speaker2 - shape (1, {FIXED_INPUT_LENGTH})")
        print(f"  Sample rate: 8kHz")
        print(f"  Duration: {FIXED_INPUT_LENGTH/8000:.2f} seconds")

    except Exception as e:
        print(f"\nERROR during conversion: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
