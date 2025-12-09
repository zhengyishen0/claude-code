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
# Snapshot directory for recon --diff
# ============================================================================
SNAPSHOT_DIR="/tmp/recon-snapshots"
mkdir -p "$SNAPSHOT_DIR" 2>/dev/null

# Get sanitized URL for snapshot filename
get_snapshot_prefix() {
  local url=$(chrome-cli execute "location.hostname + location.pathname")
  # Remove quotes, sanitize for filename
  echo "$url" | tr -d '"' | tr '/:?&=' '-' | tr -s '-' | sed 's/-$//'
}

# ============================================================================
# Command: recon
# ============================================================================
cmd_recon() {
  local STATUS=""
  local FULL_MODE=""
  local DIFF_MODE=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --status) STATUS="true"; shift ;;
      --full) FULL_MODE="true"; shift ;;
      --diff) DIFF_MODE="true"; shift ;;
      -*) echo "Unknown option: $1" >&2; return 1 ;;
      *) shift ;;
    esac
  done

  if [ "$STATUS" = "true" ]; then
    chrome-cli execute "$(cat "$SCRIPT_DIR/js/page-status.js")"
  fi

  # Get URL prefix for snapshot files
  local prefix=$(get_snapshot_prefix)
  local timestamp=$(date +%s)
  local snapshot_file="$SNAPSHOT_DIR/${prefix}-${timestamp}.md"

  # Diff mode: compare against previous snapshot
  if [ "$DIFF_MODE" = "true" ]; then
    # Find most recent snapshot for this URL
    local latest=$(ls -t "$SNAPSHOT_DIR/${prefix}"-*.md 2>/dev/null | head -1)
    if [ -z "$latest" ]; then
      echo "No previous snapshot for this URL. Run recon first."
      return 1
    fi

    # Run recon and diff against previous
    if [ "$FULL_MODE" = "true" ]; then
      chrome-cli execute "window.__RECON_FULL__ = true; $(cat "$SCRIPT_DIR/js/html2md.js")" | diff "$latest" - || true
    else
      chrome-cli execute "window.__RECON_FULL__ = false; $(cat "$SCRIPT_DIR/js/html2md.js")" | diff "$latest" - || true
    fi
    return
  fi

  # Normal recon: output and save snapshot
  if [ "$FULL_MODE" = "true" ]; then
    chrome-cli execute "window.__RECON_FULL__ = true; $(cat "$SCRIPT_DIR/js/html2md.js")" | tee "$snapshot_file"
  else
    chrome-cli execute "window.__RECON_FULL__ = false; $(cat "$SCRIPT_DIR/js/html2md.js")" | tee "$snapshot_file"
  fi
}

# ============================================================================
# Command: open
# ============================================================================
cmd_open() {
  local URL=$1
  if [ -z "$URL" ]; then
    echo "Usage: open URL [--status]" >&2
    return 1
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
        result=$(chrome-cli execute "document.querySelector('$SELECTOR') ? 'exists' : 'gone'")
        if [ "$result" = "gone" ]; then
          echo "OK: $SELECTOR disappeared"
          return 0
        fi
      else
        result=$(chrome-cli execute "document.querySelector('$SELECTOR') ? 'found' : 'waiting'")
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
      return 1
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
  result=$(chrome-cli execute "var SELECTOR='$SELECTOR_ESC'; $(cat "$SCRIPT_DIR/js/click-element.js")")

  echo "$result"

  if [[ "$result" == FAIL* ]]; then
    return 1
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
    return 1
  fi

  # Escape for JS
  SELECTOR_ESC=$(printf '%s' "$SELECTOR" | sed "s/'/\\\\'/g")
  VALUE_ESC=$(printf '%s' "$VALUE" | sed "s/'/\\\\'/g")

  # Set input value (React-safe)
  result=$(chrome-cli execute "var SELECTOR='$SELECTOR_ESC'; var VALUE='$VALUE_ESC'; $(cat "$SCRIPT_DIR/js/set-input.js")")

  echo "$result"

  if [[ "$result" == FAIL* ]]; then
    return 1
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
# Command: inspect
# ============================================================================
cmd_inspect() {
  local FORMAT="pretty"
  local USE_PATTERN="false"

  # Parse arguments
  while [ $# -gt 0 ]; do
    case "$1" in
      --json) FORMAT="json"; shift ;;
      --pattern) USE_PATTERN="true"; shift ;;
      -*) echo "Unknown option: $1" >&2; return 1 ;;
      *) shift ;;
    esac
  done

  # Execute the inspection
  local result=$(chrome-cli execute "$(cat "$SCRIPT_DIR/js/inspect.js")")

  if [ "$FORMAT" = "json" ]; then
    # Output raw JSON
    echo "$result"
  else
    # Pretty print for human reading
    echo "$result" | python3 -c "
import json, sys

data = json.load(sys.stdin)
use_pattern = '$USE_PATTERN' == 'true'

print('URL Parameter Discovery')
print('=' * 60)
print()

# Summary
summary = data.get('summary', {})
print(f\"Summary:\")
print(f\"  Parameters from links: {summary.get('paramsFromLinks', 0)}\")
print(f\"  Parameters from forms: {summary.get('paramsFromForms', 0)}\")
print(f\"  Total forms found: {summary.get('totalForms', 0)}\")
print()

# URL Parameters
params = data.get('urlParams', {})
if params:
    print('Discovered Parameters:')
    print('-' * 60)
    for name, info in params.items():
        source = info.get('source', 'unknown')
        examples = info.get('examples', [])
        ex_str = ', '.join(repr(e) for e in examples[:3])
        print(f\"  {name:<20} [{source:>5}] {ex_str}\")
    print()

# Forms
forms = data.get('forms', [])
if forms:
    print('Forms:')
    print('-' * 60)
    for form in forms:
        idx = form.get('index', 0)
        action = form.get('action', '')
        method = form.get('method', 'GET')
        fields = form.get('fields', [])
        print(f\"  Form #{idx}: {method} {action}\")
        for field in fields:
            fname = field.get('name', '')
            ftype = field.get('type', '')
            print(f\"    - {fname:<20} ({ftype})\")
    print()

# Suggested URL
if use_pattern:
    pattern = summary.get('patternUrl', '')
    if pattern:
        print('URL Pattern (with meaningful placeholders):')
        print('-' * 60)
        print(f\"  {pattern}\")
        print()
else:
    suggested = summary.get('suggestedUrl', '')
    if suggested:
        print('Suggested URL Pattern:')
        print('-' * 60)
        print(f\"  {suggested}\")
        print()
        print('Tip: Use --pattern flag for meaningful placeholders')
        print()
" 2>/dev/null || echo "$result"
  fi
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
  echo "  recon [--full] [--status] [--diff]  Get page structure as markdown"
  echo "  inspect [--json] [--pattern]  Discover URL params and forms (Tier 1+2)"
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
  echo "  $TOOL_NAME inspect"
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
    echo ""
    cmd_prereq
    ;;

  *)
    echo "Unknown command: $1" >&2
    echo "Run '$TOOL_NAME help' for usage" >&2
    exit 1
    ;;
esac
