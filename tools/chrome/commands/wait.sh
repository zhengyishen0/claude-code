#!/bin/bash
# wait.sh - Wait for DOM changes or specific elements
# Usage: wait.sh [selector] [--gone]

if [[ "$1" == "--help" ]]; then
  echo "wait [sel] [--gone]  Wait for DOM/element (10s timeout)"
  echo "  No selector: wait for readyState=complete + DOM stable"
  echo "  With selector: wait for CSS selector to appear"
  echo "  --gone: wait for element to disappear"
  echo ""
  echo "Examples:"
  echo "  wait                          # readyState + DOM stable"
  echo "  wait '[role=dialog]'          # wait for modal"
  echo "  wait '[data-testid=\"x\"]'      # wait for element"
  echo "  wait '[role=dialog]' --gone   # wait for modal to close"
  exit 0
fi

SCRIPT_DIR="$(dirname "$0")/.."
[ -f "$SCRIPT_DIR/config" ] && source "$SCRIPT_DIR/config"

timeout=${CHROME_WAIT_TIMEOUT:-10}
SELECTOR=""
GONE=false

# Parse arguments
while [ $# -gt 0 ]; do
  case "$1" in
    --gone) GONE=true; shift ;;
    -*) echo "Unknown option: $1" >&2; exit 1 ;;
    *) SELECTOR="$1"; shift ;;
  esac
done

interval=${CHROME_WAIT_INTERVAL:-0.5}
elapsed=0

if [ -n "$SELECTOR" ]; then
  # Wait for specific CSS selector to appear/disappear
  while (( $(echo "$elapsed < $timeout" | bc -l) )); do
    if [ "$GONE" = true ]; then
      result=$(chrome-cli execute "document.querySelector('$SELECTOR') ? 'exists' : 'gone'")
      if [ "$result" = "gone" ]; then
        echo "OK: $SELECTOR disappeared"
        exit 0
      fi
    else
      result=$(chrome-cli execute "document.querySelector('$SELECTOR') ? 'found' : 'waiting'")
      if [ "$result" = "found" ]; then
        echo "OK: $SELECTOR found"
        exit 0
      fi
    fi
    sleep $interval
    elapsed=$(echo "$elapsed + $interval" | bc)
  done
  echo "TIMEOUT: $SELECTOR not $( [ "$GONE" = true ] && echo 'gone' || echo 'found' ) after ${timeout}s" >&2
  exit 1

else
  # No selector: wait for page to fully load

  # First, wait for URL to change from about:blank (if just opened)
  current_url=$(chrome-cli execute "location.href")
  if [ "$current_url" = "about:blank" ]; then
    while (( $(echo "$elapsed < $timeout" | bc -l) )); do
      current_url=$(chrome-cli execute "location.href")
      if [ "$current_url" != "about:blank" ]; then
        break
      fi
      sleep 0.1
      elapsed=$(echo "$elapsed + 0.1" | bc)
    done
  fi

  # Then, wait for readyState=complete
  while (( $(echo "$elapsed < $timeout" | bc -l) )); do
    state=$(chrome-cli execute "document.readyState")
    if [ "$state" = "complete" ]; then
      break
    fi
    sleep $interval
    elapsed=$(echo "$elapsed + $interval" | bc)
  done

  if [ "$state" != "complete" ]; then
    echo "TIMEOUT: readyState not complete after ${timeout}s" >&2
    exit 1
  fi

  # Then wait for DOM to stabilize (no changes for 1s)
  SNAPSHOT=$(chrome-cli execute "document.body.innerHTML.length + '|' + document.querySelectorAll('*').length")
  stable_count=0

  while (( $(echo "$elapsed < $timeout" | bc -l) )); do
    sleep $interval
    elapsed=$(echo "$elapsed + $interval" | bc)

    CURRENT=$(chrome-cli execute "document.body.innerHTML.length + '|' + document.querySelectorAll('*').length")
    if [ "$CURRENT" = "$SNAPSHOT" ]; then
      stable_count=$((stable_count + 1))
      # Stable for 2 checks (1 second) = done
      if [ $stable_count -ge 2 ]; then
        echo "OK: DOM stable"
        exit 0
      fi
    else
      SNAPSHOT="$CURRENT"
      stable_count=0
    fi
  done

  echo "OK: DOM changed (still loading)"
  exit 0
fi
