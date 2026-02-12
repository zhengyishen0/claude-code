#!/bin/bash
# Daily log CLI wrapper

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 "$SCRIPT_DIR/dailylog.py" "$@"
