#!/bin/bash
# chrome-cli-plus - Enhanced chrome-cli with React/SPA support
# Usage: chrome-cli-plus <command> [args...]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

case "$1" in
  recon|r)
    # Get page structure in markdown
    chrome-cli execute "$(cat "$SCRIPT_DIR/html2md.js")"
    ;;

  open|o)
    # Open URL, wait for load, and recon
    # Usage: chrome-cli-plus open "URL" [timeout]
    URL=$2
    TIMEOUT=${3:-10}
    if [ -z "$URL" ]; then
      echo "Usage: chrome-cli-plus open \"URL\" [timeout]" >&2
      exit 1
    fi
    chrome-cli open "$URL"
    "$0" wait "$TIMEOUT"
    "$0" recon
    ;;

  wait|w)
    # Wait for page to load
    # Usage: chrome-cli-plus wait [timeout] [selector]
    TIMEOUT=${2:-10}
    SELECTOR=${3:-""}
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
    ;;

  click|c)
    # Click element with React-compatible strategies
    # Usage: chrome-cli-plus click "CSS_SELECTOR"
    SELECTOR=$2
    if [ -z "$SELECTOR" ]; then
      echo "Usage: chrome-cli-plus click \"CSS_SELECTOR\"" >&2
      exit 1
    fi
    chrome-cli execute "const selector='$SELECTOR'; $(cat "$SCRIPT_DIR/click-element.js")"
    ;;

  input|i)
    # Set input value with React-compatible events
    # Usage: chrome-cli-plus input "CSS_SELECTOR" "VALUE"
    SELECTOR=$2
    VALUE=$3
    if [ -z "$SELECTOR" ] || [ -z "$VALUE" ]; then
      echo "Usage: chrome-cli-plus input \"CSS_SELECTOR\" \"VALUE\"" >&2
      exit 1
    fi
    ESCAPED_VALUE=$(echo "$VALUE" | sed "s/'/\\\\'/g")
    chrome-cli execute "const selector='$SELECTOR'; const value='$ESCAPED_VALUE'; $(cat "$SCRIPT_DIR/set-input.js")"
    ;;

  tabs|t)
    # List all tabs
    chrome-cli list tabs
    ;;

  info)
    # Current tab info
    chrome-cli info
    ;;

  close)
    # Close tab by ID or active tab
    # Usage: chrome-cli-plus close [TAB_ID]
    if [ -n "$2" ]; then
      chrome-cli close -t "$2"
    else
      chrome-cli close
    fi
    ;;

  help|h|--help|-h)
    echo "chrome-cli-plus - Enhanced chrome-cli with React/SPA support"
    echo ""
    echo "Commands:"
    echo "  recon, r              Get page structure in markdown"
    echo "  open, o URL [timeout] Open URL, wait, and recon"
    echo "  wait, w [timeout] [selector]  Wait for page load"
    echo "  click, c SELECTOR     Click element (React-compatible)"
    echo "  input, i SELECTOR VALUE  Set input value (React-compatible)"
    echo "  tabs, t               List all tabs"
    echo "  info                  Current tab info"
    echo "  close [TAB_ID]        Close tab"
    echo ""
    echo "Examples:"
    echo "  chrome-cli-plus open \"https://example.com\""
    echo "  chrome-cli-plus click \"button.submit\""
    echo "  chrome-cli-plus input \"#email\" \"test@example.com\""
    ;;

  *)
    echo "Unknown command: $1" >&2
    echo "Run 'chrome-cli-plus help' for usage" >&2
    exit 1
    ;;
esac
