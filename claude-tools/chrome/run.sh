#!/bin/bash
# chrome - Browser automation with React/SPA support
# Usage: chrome [--profile NAME] <command> [args...]
# Chain commands with +: chrome click "[@X](#btn)" + wait + recon

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOL_NAME="$(basename "$SCRIPT_DIR")"

# CDP configuration
CDP_CLI="node $SCRIPT_DIR/cdp-cli.js"

# ============================================================================
# Profile utilities
# ============================================================================

# Normalize profile name: lowercase, underscores, alphanumeric only
normalize_profile_name() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | tr -s ' -.' '_' | sed 's/[^a-z0-9_]//g'
}

# Expand profile name to full path
# If starts with / or ~, use as-is. Otherwise expand to ~/.claude/profiles/<name>
expand_profile_path() {
  local profile="$1"
  if [[ "$profile" == /* ]] || [[ "$profile" == ~* ]]; then
    echo "$profile"
  else
    local normalized=$(normalize_profile_name "$profile")
    echo "$HOME/.claude/profiles/$normalized"
  fi
}

# ============================================================================
# Parse global flags (--profile)
# ============================================================================
PROFILE=""
PROFILE_PATH=""

# Extract global flags before command
while [[ "$1" == --* ]]; do
  case "$1" in
    --profile)
      PROFILE="$2"
      PROFILE_PATH=$(expand_profile_path "$PROFILE")
      shift 2
      ;;
    *)
      break
      ;;
  esac
done

# Set Chrome CLI based on mode
CHROME_PID=""
if [ -n "$PROFILE" ]; then
  # Profile specified → use CDP (headless by default)
  CHROME="$CDP_CLI"

  # Launch headless Chrome with profile
  CHROME_APP="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
  CDP_PORT=9222

  # Export CDP port for cdp-cli.js
  export CDP_PORT

  # Launch Chrome in headless mode with profile
  "$CHROME_APP" \
    --headless=new \
    --remote-debugging-port=$CDP_PORT \
    --user-data-dir="$PROFILE_PATH" \
    --disable-gpu \
    --no-first-run \
    --no-default-browser-check \
    > /dev/null 2>&1 &

  CHROME_PID=$!

  # Trap to cleanup Chrome on exit
  trap "kill $CHROME_PID 2>/dev/null" EXIT INT TERM

  # Wait for Chrome to be ready (CDP endpoint available)
  for i in {1..30}; do
    if curl -s "http://localhost:$CDP_PORT/json/version" > /dev/null 2>&1; then
      break
    fi
    sleep 0.1
  done
else
  # No profile → use chrome-cli (system Chrome.app)
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

  $CHROME open "$URL" > /dev/null

  # Restore focus immediately using cmd+tab (no delay needed) - only for chrome-cli mode
  if [ -z "$PROFILE" ]; then
    osascript -e 'tell application "System Events" to keystroke tab using command down' 2>/dev/null || true
  fi

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
# Command: profile
# ============================================================================
cmd_profile() {
  local subcommand="$1"

  # No args → list all profiles
  if [ -z "$subcommand" ]; then
    echo "Available profiles:"
    if [ -d "$HOME/.claude/profiles" ]; then
      for dir in "$HOME/.claude/profiles"/*; do
        if [ -d "$dir" ]; then
          echo "  $(basename "$dir")"
        fi
      done
    else
      echo "  (none)"
    fi
    return 0
  fi

  # Subcommand: rename
  if [ "$subcommand" = "rename" ]; then
    local old_name="$2"
    local new_name="$3"

    if [ -z "$old_name" ] || [ -z "$new_name" ]; then
      echo "Usage: profile rename OLD_NAME NEW_NAME" >&2
      return 1
    fi

    local old_normalized=$(normalize_profile_name "$old_name")
    local new_normalized=$(normalize_profile_name "$new_name")
    local old_path="$HOME/.claude/profiles/$old_normalized"
    local new_path="$HOME/.claude/profiles/$new_normalized"

    if [ ! -d "$old_path" ]; then
      echo "Error: Profile '$old_normalized' does not exist" >&2
      return 1
    fi

    if [ -d "$new_path" ]; then
      echo "Error: Profile '$new_normalized' already exists" >&2
      return 1
    fi

    mv "$old_path" "$new_path"
    echo "Profile renamed: $old_normalized → $new_normalized"
    return 0
  fi

  # Default: open profile for login
  local profile_name="$subcommand"
  local url="$2"

  # Normalize and expand profile path
  local normalized=$(normalize_profile_name "$profile_name")
  local profile_path=$(expand_profile_path "$profile_name")

  # Create profile directory if it doesn't exist
  mkdir -p "$profile_path"

  # Check if this is a new profile or updating existing
  local is_new_profile=false
  if [ ! -d "$profile_path/Default" ]; then
    is_new_profile=true
  fi

  # Open headed browser for user to login (runs in background)
  local chrome_app="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
  if [ -n "$url" ]; then
    echo "Opening profile '$normalized' at $url"
    echo "Login as needed. Your session will be saved when you close the browser."
    "$chrome_app" --remote-debugging-port=9222 --user-data-dir="$profile_path" "$url" &
    BROWSER_PID=$!
  else
    echo "Opening profile '$normalized'"
    echo "Navigate and login as needed. Your session will be saved when you close the browser."
    "$chrome_app" --remote-debugging-port=9222 --user-data-dir="$profile_path" &
    BROWSER_PID=$!
  fi

  # For new profiles: wait for initial save, validate, and auto-close
  if [ "$is_new_profile" = true ]; then
    echo ""
    echo "Waiting for you to login..."
    while [ ! -d "$profile_path/Default" ]; do
      sleep 2
    done

    echo "Profile detected! Validating..."
    sleep 3  # Give time for more cookies to be saved

    # TODO: Test the profile in headless mode with CDP
    echo "Profile created! You can close the browser window now."
    echo "  (Browser will auto-close in 10 seconds if you don't)"

    # Auto-close after 10 seconds
    (sleep 10 && kill $BROWSER_PID 2>/dev/null) &

    wait $BROWSER_PID 2>/dev/null
  else
    # Existing profile: just wait for user to close browser
    echo ""
    echo "Updating existing profile. Close the browser window when done."
    wait $BROWSER_PID 2>/dev/null
  fi
}

# ============================================================================
# Command: help
# ============================================================================
cmd_help() {
  echo "$TOOL_NAME - Browser automation with React/SPA support"
  echo ""
  echo "Usage: $TOOL_NAME [--profile NAME] <command> [args...] [+ command [args...]]..."
  echo ""
  echo "Modes:"
  echo "  Default (no --profile)      Uses chrome-cli (system Chrome.app, visible)"
  echo "  --profile NAME              Uses CDP (headless Chrome with saved credentials)"
  echo ""
  echo "Commands:"
  echo "  profile [NAME] [URL]        Manage profiles for credential persistence"
  echo "                              No args: List all profiles"
  echo "                              NAME [URL]: Open headed browser for login"
  echo "                              rename OLD NEW: Rename a profile"
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
  echo "  (no args)                   Show this help message"
  echo ""
  echo "Profile Model:"
  echo "  Profiles act as contexts (like browser profiles), each holding multiple"
  echo "  account logins. Common use: 'personal' and 'work' profiles."
  echo ""
  echo "  Setup workflow:"
  echo "    1. $TOOL_NAME profile personal \"https://mail.google.com\""
  echo "       → Opens headed browser, you login to Gmail, Twitter, etc."
  echo "       → Press Ctrl+C when done, credentials saved"
  echo ""
  echo "    2. $TOOL_NAME profile work \"https://mail.google.com\""
  echo "       → Opens headed browser, you login to work accounts"
  echo "       → Separate context from personal"
  echo ""
  echo "  AI automation (headless):"
  echo "    $TOOL_NAME --profile personal open \"https://mail.google.com\""
  echo "    $TOOL_NAME --profile work open \"https://slack.com\""
  echo ""
  echo "  Management:"
  echo "    $TOOL_NAME profile                    # List all profiles"
  echo "    $TOOL_NAME profile rename old new     # Rename profile"
  echo ""
  echo "Profile Naming:"
  echo "  - Auto-normalized: lowercase, underscores, alphanumeric"
  echo "  - Examples: personal, work, testing"
  echo "  - Stored in: ~/.claude/profiles/<name>/"
  echo ""
  echo "Basic Examples (no profile):"
  echo "  $TOOL_NAME open \"https://example.com\""
  echo "  $TOOL_NAME snapshot --diff"
  echo "  $TOOL_NAME click '[data-testid=\"btn\"]' + wait + snapshot --diff"
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
    profile)    cmd_profile "$@" ;;
    help|--help|-h) cmd_help ;;
    "") cmd_help ;;
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

  profile)
    shift
    cmd_profile "$@"
    ;;

  help|--help|-h)
    cmd_help
    ;;

  "")
    cmd_help
    ;;

  *)
    echo "Unknown command: $1" >&2
    echo "Run '$TOOL_NAME' for usage" >&2
    exit 1
    ;;
esac
