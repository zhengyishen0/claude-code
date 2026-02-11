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

# Add skills dir to Python path (for relative imports)
export PYTHONPATH="$SKILLS_DIR:${PYTHONPATH:-}"

# Run the feishu CLI
python3 -W ignore -c "
import sys
sys.path.insert(0, '$SKILLS_DIR')
from feishu import feishu_cli
feishu_cli()
" "$@"
