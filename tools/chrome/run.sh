#!/bin/bash
# chrome - Browser automation with React/SPA support
# Usage: chrome <command> [args...]
# Chain commands with +: chrome click "[@X](#btn)" + wait + recon

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOL_NAME="$(basename "$SCRIPT_DIR")"

# ============================================================================
# Configuration
# ============================================================================

# Auto-wait and auto-recon mode (default: true)
# When enabled, click and input commands automatically:
# - Detect context (navigation, modal, inline update)
# - Wait for relevant changes
# - Recon appropriate sections
# Set to false for manual control with + chaining
CHROME_AUTO_MODE=true

CHROME_WAIT_TIMEOUT=10
CHROME_WAIT_INTERVAL=0.3
CHROME_OPEN_TIMEOUT=15
CHROME_OPEN_INTERVAL=0.1
CHROME_CLICK_DELAY=150
CHROME_INPUT_DELAY=150

# ============================================================================
# Command: recon
# ============================================================================
cmd_recon() {
  local STATUS=""
  local FULL_MODE=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --status) STATUS="true"; shift ;;
      --full) FULL_MODE="true"; shift ;;
      -*) echo "Unknown option: $1" >&2; exit 1 ;;
      *) shift ;;
    esac
  done

  if [ "$STATUS" = "true" ]; then
    chrome-cli execute "$(cat "$SCRIPT_DIR/js/page-status.js")"
  fi

  # Set mode for html2md.js
  if [ "$FULL_MODE" = "true" ]; then
    chrome-cli execute "window.__RECON_FULL__ = true; $(cat "$SCRIPT_DIR/js/html2md.js")"
  else
    chrome-cli execute "window.__RECON_FULL__ = false; $(cat "$SCRIPT_DIR/js/html2md.js")"
  fi
}

# ============================================================================
# Command: open
# ============================================================================
cmd_open() {
  local URL=$1
  if [ -z "$URL" ]; then
    echo "Usage: open URL [--status]" >&2
    exit 1
  fi

  chrome-cli open "$URL" > /dev/null

  # Wait for page to fully load
  cmd_wait > /dev/null 2>&1

  if [ "$2" = "--status" ]; then
    cmd_recon --status
  else
    cmd_recon
  fi
}

# ============================================================================
# Command: wait
# ============================================================================
cmd_wait() {
  local timeout=${CHROME_WAIT_TIMEOUT}
  local SELECTOR=""
  local GONE=false

  # Parse arguments
  while [ $# -gt 0 ]; do
    case "$1" in
      --gone) GONE=true; shift ;;
      -*) echo "Unknown option: $1" >&2; exit 1 ;;
      *) SELECTOR="$1"; shift ;;
    esac
  done

  local interval=${CHROME_WAIT_INTERVAL}
  local elapsed=0

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
}

# ============================================================================
# Command: click
# ============================================================================
cmd_click() {
  local SELECTOR="$1"
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
}

# ============================================================================
# Command: input
# ============================================================================
cmd_input() {
  local SELECTOR="$1"
  local VALUE="$2"

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
}

# ============================================================================
# Command: esc
# ============================================================================
cmd_esc() {
  JS_CODE=$(cat "$SCRIPT_DIR/js/send-esc.js")
  chrome-cli execute "$JS_CODE"
}

# ============================================================================
# Command: help
# ============================================================================
cmd_help() {
  echo "$TOOL_NAME - Browser automation with React/SPA support"
  echo ""
  echo "Usage: $TOOL_NAME <command> [args...] [+ command [args...]]..."
  echo ""
  echo "Commands:"
  echo "  recon [--full] [--status]  Get page structure as markdown"
  echo "  open URL [--status]      Open URL (waits for load), then recon"
  echo "  wait [sel] [--gone]  Wait for DOM/element (10s timeout)"
  echo "  click SELECTOR          Click element by CSS selector"
  echo "  input SELECTOR VALUE    Set input value by CSS selector"
  echo "  esc                         Send ESC key (close dialogs/modals)"
  echo "  help                        Show this help message"
  echo ""
  echo "Quick Examples:"
  echo "  $TOOL_NAME open \"https://example.com\""
  echo "  $TOOL_NAME recon"
  echo "  $TOOL_NAME click '[data-testid=\"btn\"]' + wait + recon"
  echo "  $TOOL_NAME input '#email' 'test@example.com' + wait + recon"
  echo ""
  echo "For detailed documentation, see: $SCRIPT_DIR/README.md"
}

# ============================================================================
# Command: prereq
# ============================================================================
cmd_prereq() {
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
}

# ============================================================================
# Execute single command
# ============================================================================
execute_single() {
  local cmd="$1"
  shift
  case "$cmd" in
    recon)      cmd_recon "$@" ;;
    open)       cmd_open "$@" ;;
    wait)       cmd_wait "$@" ;;
    click)      cmd_click "$@" ;;
    input)      cmd_input "$@" ;;
    esc)        cmd_esc "$@" ;;
    help|--help|-h) cmd_help ;;
    *)
      echo "Unknown command: $cmd" >&2
      return 1
      ;;
  esac
}

# ============================================================================
# Execute chain of commands separated by +
# ============================================================================
execute_chain() {
  local cmd="$1"
  shift
  local args=()

  for arg in "$@"; do
    if [ "$arg" = "+" ]; then
      # Execute accumulated command
      execute_single "$cmd" "${args[@]}"
      if [ $? -ne 0 ]; then return 1; fi
      # Reset for next command
      cmd=""
      args=()
    elif [ -z "$cmd" ]; then
      cmd="$arg"
    else
      args+=("$arg")
    fi
  done

  # Execute last command
  if [ -n "$cmd" ]; then
    execute_single "$cmd" "${args[@]}"
  fi
}

# ============================================================================
# Main execution
# ============================================================================

# Check if + is in args for command chaining
has_chain=false
for arg in "$@"; do
  if [ "$arg" = "+" ]; then
    has_chain=true
    break
  fi
done

if [ "$has_chain" = true ]; then
  execute_chain "$@"
  exit $?
fi

# No chain - single command
case "$1" in
  recon)
    shift
    cmd_recon "$@"
    ;;

  open)
    shift
    cmd_open "$@"
    ;;

  wait)
    shift
    cmd_wait "$@"
    ;;

  click)
    shift
    cmd_click "$@"
    ;;

  input)
    shift
    cmd_input "$@"
    ;;

  esc)
    cmd_esc
    ;;

  help|--help|-h)
    cmd_help
    ;;

  "")
    cmd_help
    echo ""
    cmd_prereq
    ;;

  *)
    echo "Unknown command: $1" >&2
    echo "Run '$TOOL_NAME help' for usage" >&2
    exit 1
    ;;
esac
