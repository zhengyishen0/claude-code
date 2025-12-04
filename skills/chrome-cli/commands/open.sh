#!/bin/bash
# open.sh - Open URL and recon
# Usage: open.sh URL [--status]

SCRIPT_DIR="$(dirname "$0")/.."

URL=$1
if [ -z "$URL" ]; then
  echo "Usage: open.sh URL [--status]" >&2
  exit 1
fi

chrome-cli open "$URL"

if [ "$2" = "--status" ]; then
  "$SCRIPT_DIR/commands/recon.sh" --status
else
  "$SCRIPT_DIR/commands/recon.sh"
fi
