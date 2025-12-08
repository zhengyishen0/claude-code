#!/bin/bash
# input.sh - Set input value by CSS selector
# Usage: input.sh "selector" "value"

SCRIPT_DIR="$(dirname "$0")/.."
[ -f "$SCRIPT_DIR/config" ] && source "$SCRIPT_DIR/config"

SELECTOR="$1"
VALUE="$2"

if [ -z "$SELECTOR" ] || [ -z "$VALUE" ]; then
  echo "Usage: input 'CSS selector' 'value'" >&2
  exit 1
fi

# Escape for JS
SELECTOR_ESC=$(printf '%s' "$SELECTOR" | sed "s/'/\\\\'/g")
VALUE_ESC=$(printf '%s' "$VALUE" | sed "s/'/\\\\'/g")

# Set input value (React-safe)
result=$(chrome-cli execute "var SELECTOR='$SELECTOR_ESC'; var VALUE='$VALUE_ESC'; $(cat "$SCRIPT_DIR/js/set-input.js")")

echo "$result"

if [[ "$result" == FAIL* ]]; then
  exit 1
fi
