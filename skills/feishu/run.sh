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

# Suppress Python warnings
export PYTHONWARNINGS="ignore"

# Run the feishu CLI directly
python3 -W ignore -c "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from __init__ import feishu_cli
feishu_cli()
" "$@"
