#!/bin/bash
# wait.sh - Wait for DOM changes or specific elements
# Usage: wait.sh [selector] [--gone]

if [[ "$1" == "--help" ]]; then
  echo "wait [sel] [--gone]  Wait for DOM/element (5s timeout)"
  echo "  No selector: wait for any DOM change"
  echo "  With selector: wait for element to appear"
  echo "  --gone: wait for element to disappear"
  echo ""
  echo "Use CSS descendant selectors for scoping:"
  echo "  wait \"dialog button\"                    # any dialog's button"
  echo "  wait \"[role=dialog] button\"             # ARIA dialog's button"
  echo "  wait \"[aria-label~='Reserve'] button\"   # labeled section's button"
  exit 0
fi

SCRIPT_DIR="$(dirname "$0")/.."
[ -f "$SCRIPT_DIR/config" ] && source "$SCRIPT_DIR/config"

timeout=${CHROME_WAIT_TIMEOUT:-5}
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
  # Wait for specific selector to appear/disappear
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
  # Wait for any DOM change using MutationObserver
  # Inject observer, wait for mutation or timeout
  JS_OBSERVER='
(function() {
  return new Promise(function(resolve) {
    var resolved = false;
    var observer = new MutationObserver(function() {
      if (!resolved) {
        resolved = true;
        observer.disconnect();
        resolve("changed");
      }
    });
    observer.observe(document.body, {
      childList: true,
      subtree: true,
      attributes: true,
      characterData: true
    });
    setTimeout(function() {
      if (!resolved) {
        resolved = true;
        observer.disconnect();
        resolve("timeout");
      }
    }, '"$((timeout * 1000))"');
  });
})()
'
  # chrome-cli doesn't support async, so we poll for changes instead
  # Take snapshot, then compare
  SNAPSHOT=$(chrome-cli execute "document.body.innerHTML.length + '|' + document.querySelectorAll('*').length")

  while (( $(echo "$elapsed < $timeout" | bc -l) )); do
    sleep $interval
    elapsed=$(echo "$elapsed + $interval" | bc)
    CURRENT=$(chrome-cli execute "document.body.innerHTML.length + '|' + document.querySelectorAll('*').length")
    if [ "$CURRENT" != "$SNAPSHOT" ]; then
      echo "OK: DOM changed"
      exit 0
    fi
  done
  echo "OK: No DOM change (stable)"
  exit 0
fi
