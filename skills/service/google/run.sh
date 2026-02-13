#!/usr/bin/env bash
set -euo pipefail

# Resolve symlinks to get the actual script directory
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
    DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
SKILLS_DIR="$(dirname "$SCRIPT_DIR")"

# Suppress Python warnings
export PYTHONWARNINGS="ignore"

# Add skills dir to Python path (for relative imports to work)
export PYTHONPATH="$SKILLS_DIR:${PYTHONPATH:-}"

# Run the google CLI using importlib (avoids system google package conflict)
python3 -W ignore -c "
import sys
import importlib.util
from pathlib import Path

def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module

google_module = load_module('google_service', Path('$SCRIPT_DIR') / '__init__.py')
google_module.google_cli()
" "$@"
