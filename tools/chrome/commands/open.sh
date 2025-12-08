#!/bin/bash
# open.sh - Open URL and recon
# Usage: open.sh URL [--status]

if [[ "$1" == "--help" ]]; then
  echo "open URL [--status]      Open URL (waits for load), then recon"
  echo "  --status: show loading info after page loads"
  exit 0
fi

SCRIPT_DIR="$(dirname "$0")/.."
[ -f "$SCRIPT_DIR/config" ] && source "$SCRIPT_DIR/config"

URL=$1
if [ -z "$URL" ]; then
  echo "Usage: open.sh URL [--status]" >&2
  exit 1
fi

chrome-cli open "$URL" > /dev/null

# Wait for page to fully load
"$SCRIPT_DIR/commands/wait.sh" > /dev/null 2>&1

if [ "$2" = "--status" ]; then
  "$SCRIPT_DIR/commands/recon.sh" --status
else
  "$SCRIPT_DIR/commands/recon.sh"
fi
