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

# Wait for page to fully load (poll readyState)
TIMEOUT=10
elapsed=0
interval=0.2
while (( $(echo "$elapsed < $TIMEOUT" | bc -l) )); do
  state=$(chrome-cli execute "document.readyState")
  if [ "$state" = "complete" ]; then
    break
  fi
  sleep $interval
  elapsed=$(echo "$elapsed + $interval" | bc)
done

if [ "$2" = "--status" ]; then
  "$SCRIPT_DIR/commands/recon.sh" --status
else
  "$SCRIPT_DIR/commands/recon.sh"
fi
