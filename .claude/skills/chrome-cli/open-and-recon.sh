#!/bin/bash
# Open a URL, wait for it to load, and run reconnaissance
# Usage: open-and-recon.sh "URL" [timeout]
# Examples:
#   open-and-recon.sh "https://example.com"
#   open-and-recon.sh "https://example.com" 15

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
URL=$1
TIMEOUT=${2:-10}

if [ -z "$URL" ]; then
  echo "Usage: open-and-recon.sh \"URL\" [timeout]" >&2
  exit 1
fi

# Open URL
chrome-cli open "$URL"

# Wait for page to load
"$SCRIPT_DIR/wait-for-load.sh" "$TIMEOUT"

# Run reconnaissance
"$SCRIPT_DIR/html2md.sh"
