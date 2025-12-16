#!/bin/bash
# chrome - Browser automation with React/SPA support
# Usage: chrome [--headless] [--profile PATH] <command> [args...]
# Chain commands with +: chrome click "[@X](#btn)" + wait + recon

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOL_NAME="$(basename "$SCRIPT_DIR")"

# Add bin directory to PATH for playwright-cli
export PATH="$SCRIPT_DIR/bin:$PATH"

# ============================================================================
# Parse global flags (--headless, --profile)
# ============================================================================
HEADLESS=false
PROFILE=""

# Extract global flags before command
while [[ "$1" == --* ]]; do
  case "$1" in
    --headless)
      HEADLESS=true
      shift
      ;;
    --profile)
      PROFILE="$2"
      shift 2
      ;;
    *)
      break
      ;;
  esac
done

# Set Chrome CLI based on mode
if [ "$HEADLESS" = "true" ]; then
  CHROME="playwright-cli"
  export PLAYWRIGHT_HEADLESS="true"
  if [ -n "$PROFILE" ]; then
    export PLAYWRIGHT_PROFILE="$PROFILE"
  fi
else
  CHROME="chrome-cli"
fi

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
# Snapshot directory
# ============================================================================
SNAPSHOT_DIR="/tmp/chrome-snapshots"
mkdir -p "$SNAPSHOT_DIR" 2>/dev/null

# Get sanitized URL for snapshot filename
get_snapshot_prefix() {
  local url=$($CHROME execute "location.hostname + location.pathname")
  # Remove quotes, sanitize for filename
  echo "$url" | tr -d '"' | tr '/:?&=' '-' | tr -s '-' | sed 's/-$//'
}

# Detect page state for snapshot comparison
get_page_state() {
  $CHROME execute "$(cat "$SCRIPT_DIR/js/detect-page-state.js")" | tr -d '"'
}

# ============================================================================
# Command: snapshot
# ============================================================================
cmd_snapshot() {
  local DIFF_MODE=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --diff) DIFF_MODE="true"; shift ;;
      -*) echo "Unknown option: $1" >&2; return 1 ;;
      *) shift ;;
    esac
  done

  # Get URL prefix and page state for snapshot files
  local prefix=$(get_snapshot_prefix)
  local state=$(get_page_state)
  local timestamp=$(date +%s)
  local snapshot_file="$SNAPSHOT_DIR/${prefix}-${state}-${timestamp}.md"

  # Always capture full content
  local content=$($CHROME execute "window.__RECON_FULL__ = true; $(cat "$SCRIPT_DIR/js/html2md.js")")

  # Diff mode: compare against previous snapshot with same state
  if [ "$DIFF_MODE" = "true" ]; then
    # Find most recent snapshot for this URL + state
    local latest=$(ls -t "$SNAPSHOT_DIR/${prefix}-${state}"-*.md 2>/dev/null | head -1)
    if [ -z "$latest" ]; then
      echo "No previous snapshot for this URL state ($state). Run snapshot first." >&2
      return 1
    fi

    # Save snapshot and show diff
    echo "$content" | tee "$snapshot_file" | diff "$latest" - || true
  else
    # Normal mode: save and output snapshot
    echo "$content" | tee "$snapshot_file"
  fi
}

# Alias for backward compatibility
cmd_recon() {
  cmd_snapshot "$@"
}

# ============================================================================
# Command: open
# ============================================================================
cmd_open() {
  local URL=$1
  if [ -z "$URL" ]; then
    echo "Usage: open URL" >&2
    return 1
  fi

  $chrome open "$URL" > /dev/null

  # Restore focus immediately using cmd+tab (no delay needed)
  osascript -e 'tell application "System Events" to keystroke tab using command down' 2>/dev/null || true

  # Wait for page to fully load (happens in background)
  cmd_wait > /dev/null 2>&1

  # Show URL structure (helps Claude build better URLs)
  cmd_inspect

  # Show page content
  cmd_snapshot
}

# ============================================================================
# Command: wait
# ============================================================================
cmd_wait() {
  local timeout=${CHROME_WAIT_TIMEOUT}
  local SELECTOR=""
  local GONE=false
  local NETWORK=false

  # Parse arguments
  while [ $# -gt 0 ]; do
    case "$1" in
      --gone) GONE=true; shift ;;
      --network) NETWORK=true; shift ;;
      -*) echo "Unknown option: $1" >&2; return 1 ;;
      *) SELECTOR="$1"; shift ;;
    esac
  done

  local interval=${CHROME_WAIT_INTERVAL}
  local elapsed=0

  if [ -n "$SELECTOR" ]; then
    # Wait for specific CSS selector to appear/disappear
    while (( $(echo "$elapsed < $timeout" | bc -l) )); do
      if [ "$GONE" = true ]; then
        result=$($CHROME execute "document.querySelector('$SELECTOR') ? 'exists' : 'gone'")
        if [ "$result" = "gone" ]; then
          echo "OK: $SELECTOR disappeared"
          return 0
        fi
      else
        result=$($CHROME execute "document.querySelector('$SELECTOR') ? 'found' : 'waiting'")
        if [ "$result" = "found" ]; then
          echo "OK: $SELECTOR found"
          return 0
        fi
      fi
      sleep $interval
      elapsed=$(echo "$elapsed + $interval" | bc)
    done
    echo "TIMEOUT: $SELECTOR not $( [ "$GONE" = true ] && echo 'gone' || echo 'found' ) after ${timeout}s" >&2
    return 1

  else
    # No selector: wait for page to fully load

    # First, wait for URL to change from about:blank (if just opened)
    current_url=$($CHROME execute "location.href")
    if [ "$current_url" = "about:blank" ]; then
      while (( $(echo "$elapsed < $timeout" | bc -l) )); do
        current_url=$($CHROME execute "location.href")
        if [ "$current_url" != "about:blank" ]; then
          break
        fi
        sleep 0.1
        elapsed=$(echo "$elapsed + 0.1" | bc)
      done
    fi

    # Then, wait for readyState=complete
    while (( $(echo "$elapsed < $timeout" | bc -l) )); do
      state=$($CHROME execute "document.readyState")
      if [ "$state" = "complete" ]; then
        break
      fi
      sleep $interval
      elapsed=$(echo "$elapsed + $interval" | bc)
    done

    if [ "$state" != "complete" ]; then
      echo "TIMEOUT: readyState not complete after ${timeout}s" >&2
      return 1
    fi

    # Wait for network idle if --network flag is set
    if [ "$NETWORK" = true ]; then
      while (( $(echo "$elapsed < $timeout" | bc -l) )); do
        # Check for active network requests
        active=$($CHROME execute "performance.getEntriesByType('resource').filter(r => !r.responseEnd).length")
        if [ "$active" = "0" ]; then
          echo "OK: Network idle"
          break
        fi
        sleep $interval
        elapsed=$(echo "$elapsed + $interval" | bc)
      done
    fi

    # Then wait for DOM to stabilize (no changes for 1.2-1.5s for lazy content)
    SNAPSHOT=$($CHROME execute "document.body.innerHTML.length + '|' + document.querySelectorAll('*').length")
    stable_count=0
    required_stable=4  # 4 checks * 0.3s = 1.2s stability required

    while (( $(echo "$elapsed < $timeout" | bc -l) )); do
      sleep $interval
      elapsed=$(echo "$elapsed + $interval" | bc)

      CURRENT=$($CHROME execute "document.body.innerHTML.length + '|' + document.querySelectorAll('*').length")
      if [ "$CURRENT" = "$SNAPSHOT" ]; then
        stable_count=$((stable_count + 1))
        # Stable for required checks = done
        if [ $stable_count -ge $required_stable ]; then
          echo "OK: DOM stable"
          return 0
        fi
      else
        SNAPSHOT="$CURRENT"
        stable_count=0
      fi
    done

    echo "OK: DOM changed (still loading)"
    return 0
  fi
}

# ============================================================================
# Command: click
# ============================================================================
cmd_click() {
  local SELECTOR="$1"
  if [ -z "$SELECTOR" ]; then
    echo "Usage: click 'CSS selector'" >&2
    return 1
  fi

  # Escape selector for JS
  SELECTOR_ESC=$(printf '%s' "$SELECTOR" | sed "s/'/\\\\'/g")

  # Click the element
  result=$($CHROME execute "var SELECTOR='$SELECTOR_ESC'; $(cat "$SCRIPT_DIR/js/click-element.js")")

  echo "$result"

  if [[ "$result" == FAIL* ]]; then
    return 1
  fi

  # Auto-wait for page to react to click
  cmd_wait > /dev/null 2>&1

  # Show what changed after click (try diff, fallback to full snapshot)
  cmd_snapshot --diff 2>/dev/null || cmd_snapshot
}

# ============================================================================
# Command: input
# ============================================================================
cmd_input() {
  local SELECTOR="$1"
  local VALUE="$2"

  if [ -z "$SELECTOR" ] || [ -z "$VALUE" ]; then
    echo "Usage: input 'CSS selector' 'value'" >&2
    return 1
  fi

  # Escape for JS
  SELECTOR_ESC=$(printf '%s' "$SELECTOR" | sed "s/'/\\\\'/g")
  VALUE_ESC=$(printf '%s' "$VALUE" | sed "s/'/\\\\'/g")

  # Set input value (React-safe)
  result=$($CHROME execute "var SELECTOR='$SELECTOR_ESC'; var VALUE='$VALUE_ESC'; $(cat "$SCRIPT_DIR/js/set-input.js")")

  echo "$result"

  if [[ "$result" == FAIL* ]]; then
    return 1
  fi

  # Auto-wait for page to react to input (autocomplete, validation, etc.)
  cmd_wait > /dev/null 2>&1

  # Show what changed after input (try diff, fallback to full snapshot)
  cmd_snapshot --diff 2>/dev/null || cmd_snapshot
}

# ============================================================================
# Command: esc
# ============================================================================
cmd_esc() {
  JS_CODE=$(cat "$SCRIPT_DIR/js/send-esc.js")
  $CHROME execute "$JS_CODE"
}

# ============================================================================
# Command: inspect
# ============================================================================
cmd_inspect() {
  # Execute the inspection
  local result=$($CHROME execute "$(cat "$SCRIPT_DIR/js/inspect.js")")

  # Pretty print for human reading
  echo "$result" | python3 "$SCRIPT_DIR/py/format-inspect.py"
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
  echo "  snapshot [--diff]           Capture page state (always saves full content)"
  echo "                              --diff: Show changes vs previous snapshot"
  echo "  inspect                     Discover URL parameters from links and forms"
  echo "  open URL                    Open URL (waits for load), then snapshot"
  echo "  wait [sel] [--gone] [--network]"
  echo "                              Wait for DOM/element (10s timeout)"
  echo "                              --gone: Wait for element to disappear"
  echo "                              --network: Wait for network idle"
  echo "  click SELECTOR              Click element by CSS selector"
  echo "  input SELECTOR VALUE        Set input value by CSS selector"
  echo "  esc                         Send ESC key (close dialogs/modals)"
  echo "  help                        Show this help message"
  echo ""
  echo "Quick Examples:"
  echo "  $TOOL_NAME open \"https://example.com\""
  echo "  $TOOL_NAME inspect"
  echo "  $TOOL_NAME snapshot"
  echo "  $TOOL_NAME snapshot --diff"
  echo "  $TOOL_NAME click '[data-testid=\"btn\"]' + wait + snapshot --diff"
  echo "  $TOOL_NAME input '#email' 'test@example.com' + wait + snapshot --diff"
  echo ""
  echo "Note: 'recon' is aliased to 'snapshot' for backward compatibility"
  echo ""
  echo "For detailed documentation, see: $SCRIPT_DIR/README.md"
}

# ============================================================================
# Execute single command
# ============================================================================
execute_single() {
  local cmd="$1"
  shift
  case "$cmd" in
    snapshot)   cmd_snapshot "$@" ;;
    recon)      cmd_recon "$@" ;;  # backward compatibility
    inspect)    cmd_inspect "$@" ;;
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
  snapshot)
    shift
    cmd_snapshot "$@"
    ;;

  recon)
    shift
    cmd_recon "$@"
    ;;

  inspect)
    shift
    cmd_inspect "$@"
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
    ;;

  *)
    echo "Unknown command: $1" >&2
    echo "Run '$TOOL_NAME help' for usage" >&2
    exit 1
    ;;
esac
