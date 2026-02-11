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

# Suppress Python warnings (for Python 3.9 / LibreSSL compatibility)
export PYTHONWARNINGS="ignore"

# Add services dir to Python path (local imports take precedence)
export PYTHONPATH="$SCRIPT_DIR:${PYTHONPATH:-}"

# Show help if no arguments
if [[ $# -eq 0 ]]; then
    python3 -W ignore "$SCRIPT_DIR/main.py" --help
    exit 0
fi

python3 -W ignore "$SCRIPT_DIR/main.py" "$@"
