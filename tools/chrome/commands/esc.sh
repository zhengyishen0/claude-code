#!/bin/bash
# esc.sh - Send ESC key to close dialogs/modals
# Usage: esc.sh

if [[ "$1" == "--help" ]]; then
  echo "esc, escape                 Send ESC key (close dialogs/modals)"
  exit 0
fi

SCRIPT_DIR="$(dirname "$0")/.."

JS_CODE=$(cat "$SCRIPT_DIR/js/send-esc.js")
chrome-cli execute "$JS_CODE"
