#!/bin/bash
# prereq.sh - Check prerequisites
# Usage: prereq.sh

echo "Prerequisites:"

# Check Chrome
if pgrep -x "Google Chrome" > /dev/null; then
  echo "  ✓ Chrome is running"
elif [ -d "/Applications/Google Chrome.app" ]; then
  echo "  ✓ Chrome installed (not running)"
else
  echo "  ✗ Chrome not found"
  echo "    Install from: https://www.google.com/chrome/"
fi

# Check chrome-cli
if command -v chrome-cli > /dev/null; then
  echo "  ✓ chrome-cli installed"
else
  echo "  ✗ chrome-cli not found"
  if command -v brew > /dev/null; then
    echo "    Install with: brew install chrome-cli"
  else
    echo "    Install brew first: https://brew.sh"
    echo "    Then: brew install chrome-cli"
  fi
fi
