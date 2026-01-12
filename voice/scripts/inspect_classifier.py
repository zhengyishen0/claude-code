#!/usr/bin/env python3
"""Inspect SpeakerRecognition classifier structure."""

from speechbrain.inference.speaker import SpeakerRecognition

print("Loading classifier...")
classifier = SpeakerRecognition.from_hparams(
    source="speechbrain/spkrec-xvect-voxceleb",
    savedir="pretrained_models/spkrec-xvect-voxceleb",
    run_opts={"device": "cpu"}
)

print(f"Type: {type(classifier)}")
print(f"\nAttributes (first 30):")
attrs = [x for x in dir(classifier) if not x.startswith('_')]
for attr in attrs[:30]:
    print(f"  - {attr}")

print(f"\nLooking for embedding-related attributes:")
for attr in attrs:
    if 'embed' in attr.lower() or 'encoder' in attr.lower() or 'model' in attr.lower():
        val = getattr(classifier, attr)
        print(f"  {attr}: {type(val).__name__}")

print(f"\nChecking hparams:")
if hasattr(classifier, 'hparams'):
    hparams = classifier.hparams
    print(f"  hparams type: {type(hparams)}")
    for key in list(hparams.keys())[:10]:
        val = hparams[key]
        print(f"    {key}: {type(val).__name__}")

print(f"\nChecking modules:")
if hasattr(classifier, 'modules'):
    modules = classifier.modules
    print(f"  modules type: {type(modules)}")
    if callable(modules):
        print(f"  modules is callable")
        result = modules()
        print(f"  modules() result type: {type(result)}")
        if hasattr(result, '__dict__'):
            for k, v in result.__dict__.items():
                print(f"    {k}: {type(v).__name__}")
