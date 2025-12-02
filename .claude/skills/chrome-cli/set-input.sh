#!/bin/bash
# Set input value with React-compatible event dispatching
# Usage: set-input.sh "CSS_SELECTOR" "VALUE"
# Example: set-input.sh "input[name='email']" "test@example.com"
# Example: set-input.sh "#search" "search term"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SELECTOR=$1
VALUE=$2

if [ -z "$SELECTOR" ] || [ -z "$VALUE" ]; then
  echo "Usage: set-input.sh \"CSS_SELECTOR\" \"VALUE\"" >&2
  exit 1
fi

# Escape single quotes in value
ESCAPED_VALUE=$(echo "$VALUE" | sed "s/'/\\\\'/g")

chrome-cli execute "const selector='$SELECTOR'; const value='$ESCAPED_VALUE'; $(cat "$SCRIPT_DIR/set-input.js")"
