#!/bin/bash
# click.sh - Click element by CSS selector
# Usage: click.sh "selector"

SCRIPT_DIR="$(dirname "$0")/.."
[ -f "$SCRIPT_DIR/config" ] && source "$SCRIPT_DIR/config"

SELECTOR="$1"
if [ -z "$SELECTOR" ]; then
  echo "Usage: click 'CSS selector'" >&2
  exit 1
fi

# Escape selector for JS
SELECTOR_ESC=$(printf '%s' "$SELECTOR" | sed "s/'/\\\\'/g")

# Click the element
result=$(chrome-cli execute "var SELECTOR='$SELECTOR_ESC'; $(cat "$SCRIPT_DIR/js/click-element.js")")

echo "$result"

if [[ "$result" == FAIL* ]]; then
  exit 1
fi
