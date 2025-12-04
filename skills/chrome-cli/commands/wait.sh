#!/bin/bash
# wait.sh - Wait for page to load
# Usage: wait.sh [timeout] [selector]

TIMEOUT=${1:-10}
SELECTOR=${2:-""}
elapsed=0
interval=0.3

while [ "$elapsed" -lt "$TIMEOUT" ]; do
  if [ -n "$SELECTOR" ]; then
    result=$(chrome-cli execute "document.querySelector('$SELECTOR') ? 'ready' : 'loading'")
  else
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
