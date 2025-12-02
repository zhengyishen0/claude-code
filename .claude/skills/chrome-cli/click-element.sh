#!/bin/bash
# Click an element using multiple strategies for React/SPA compatibility
# Usage: click-element.sh "CSS_SELECTOR"
# Example: click-element.sh "button.submit"
# Example: click-element.sh "[data-testid='save-btn']"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SELECTOR=$1

if [ -z "$SELECTOR" ]; then
  echo "Usage: click-element.sh \"CSS_SELECTOR\"" >&2
  exit 1
fi

chrome-cli execute "const selector='$SELECTOR'; $(cat "$SCRIPT_DIR/click-element.js")"
