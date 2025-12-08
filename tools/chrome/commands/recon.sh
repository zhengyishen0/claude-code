#!/bin/bash
# recon.sh - Get page structure in markdown
# Usage: recon.sh [--status]

SCRIPT_DIR="$(dirname "$0")/.."

STATUS=""
FULL_MODE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --status)
      STATUS="true"
      shift
      ;;
    --full)
      FULL_MODE="true"
      shift
      ;;
    -*)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
    *)
      shift
      ;;
  esac
done

if [ "$STATUS" = "true" ]; then
  chrome-cli execute "$(cat "$SCRIPT_DIR/js/page-status.js")"
fi

# Set mode for html2md.js
if [ "$FULL_MODE" = "true" ]; then
  chrome-cli execute "window.__RECON_FULL__ = true; $(cat "$SCRIPT_DIR/js/html2md.js")"
else
  chrome-cli execute "window.__RECON_FULL__ = false; $(cat "$SCRIPT_DIR/js/html2md.js")"
fi
