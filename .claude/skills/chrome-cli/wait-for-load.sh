#!/bin/bash
# Wait for page to finish loading
# Usage: wait-for-load.sh [timeout_seconds] [selector]
# Examples:
#   wait-for-load.sh          # Wait for document.readyState = complete (default 10s)
#   wait-for-load.sh 5        # Wait up to 5 seconds
#   wait-for-load.sh 10 ".my-element"  # Wait for specific element to appear

TIMEOUT=${1:-10}
SELECTOR=${2:-""}

elapsed=0
interval=0.3

while [ "$elapsed" -lt "$TIMEOUT" ]; do
  if [ -n "$SELECTOR" ]; then
    # Wait for specific element
    result=$(chrome-cli execute "document.querySelector('$SELECTOR') ? 'ready' : 'loading'")
  else
    # Wait for document ready state
    result=$(chrome-cli execute "document.readyState")
  fi

  if [ "$result" = "complete" ] || [ "$result" = "ready" ]; then
    exit 0
  fi

  sleep $interval
  elapsed=$((elapsed + 1))
done

echo "Timeout waiting for page to load" >&2
exit 1
