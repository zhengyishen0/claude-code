#!/bin/bash
# esc.sh - Send ESC key to close dialogs/modals
# Usage: esc.sh

SCRIPT_DIR="$(dirname "$0")/.."

JS_CODE=$(cat "$SCRIPT_DIR/js/send-esc.js")
chrome-cli execute "$JS_CODE"
