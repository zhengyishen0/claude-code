#!/bin/bash
# chrome - Browser automation with CDP (Chrome DevTools Protocol)
# Usage: chrome [--profile NAME] [--debug] <command> [args...]
# Chain commands with +: chrome click "[@X](#btn)" + wait + snapshot

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOL_NAME="$(basename "$SCRIPT_DIR")"

# CDP configuration
CDP_CLI="node $SCRIPT_DIR/cdp-cli.js"
CDP_PORT=${CDP_PORT:-9222}
CDP_HOST=${CDP_HOST:-localhost}
CHROME_APP="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

# Default profile location
DEFAULT_PROFILE="$HOME/.claude/chrome/default"

# Export for cdp-cli.js
export CDP_PORT CDP_HOST

# ============================================================================
# Profile utilities
# ============================================================================

# Normalize profile name: lowercase, underscores, alphanumeric only
normalize_profile_name() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | tr -s ' -.' '_' | sed 's/[^a-z0-9_]//g'
}

# Expand profile name to full path
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
# CDP connection management
# ============================================================================

# Check if CDP is available
cdp_is_running() {
  curl -s "http://$CDP_HOST:$CDP_PORT/json/version" > /dev/null 2>&1
}

# Wait for CDP to become available
wait_for_cdp() {
  local timeout=${1:-10}
  local elapsed=0
  while [ $elapsed -lt $timeout ]; do
    if cdp_is_running; then
      return 0
    fi
    sleep 0.2
    elapsed=$((elapsed + 1))
  done
  return 1
}

# Launch Chrome if not already running
ensure_chrome_running() {
  if cdp_is_running; then
    return 0
  fi

  # Determine profile path
  local profile_path="$PROFILE_PATH"
  if [ -z "$profile_path" ]; then
    profile_path="$DEFAULT_PROFILE"
  fi
  mkdir -p "$profile_path"

  # Build Chrome args
  local chrome_args=(
    --remote-debugging-port=$CDP_PORT
    --user-data-dir="$profile_path"
    --no-first-run
    --no-default-browser-check
  )

  # Headless mode: --profile without --debug
  if [ -n "$PROFILE" ] && [ "$DEBUG_MODE" = false ]; then
    chrome_args+=(--headless=new --disable-gpu)
  fi

  # Launch Chrome in background (detached from this script)
  nohup "$CHROME_APP" "${chrome_args[@]}" > /dev/null 2>&1 &

  # Wait for CDP
  if ! wait_for_cdp 30; then
    echo "ERROR: Chrome failed to start (CDP not available on port $CDP_PORT)" >&2
    return 1
  fi
}

# ============================================================================
# Parse global flags
# ============================================================================
PROFILE=""
PROFILE_PATH=""
DEBUG_MODE=false

while [[ "$1" == --* ]]; do
  case "$1" in
    --profile)
      PROFILE="$2"
      PROFILE_PATH=$(expand_profile_path "$PROFILE")
      shift 2
      ;;
    --debug)
      DEBUG_MODE=true
      shift
      ;;
    *)
      break
      ;;
  esac
done

# ============================================================================
# Configuration
# ============================================================================
CHROME_WAIT_TIMEOUT=10
CHROME_WAIT_INTERVAL=0.3

# ============================================================================
# Snapshot directory
# ============================================================================
SNAPSHOT_DIR="/tmp/chrome-snapshots"
mkdir -p "$SNAPSHOT_DIR" 2>/dev/null

get_snapshot_prefix() {
  local url=$($CDP_CLI execute "location.hostname + location.pathname")
  echo "$url" | tr -d '"' | tr '/:?&=' '-' | tr -s '-' | sed 's/-$//'
}

get_page_state() {
  $CDP_CLI execute "$(cat "$SCRIPT_DIR/js/detect-page-state.js")" | tr -d '"'
}

# ============================================================================
# Command: snapshot
# ============================================================================
cmd_snapshot() {
  ensure_chrome_running || return 1

  local FORCE_FULL=false
  while [ $# -gt 0 ]; do
    case "$1" in
      --full) FORCE_FULL=true; shift ;;
      -*) echo "Unknown option: $1" >&2; return 1 ;;
      *) shift ;;
    esac
  done

  local prefix=$(get_snapshot_prefix)
  local state=$(get_page_state)
  local timestamp=$(date +%s)
  local snapshot_file="$SNAPSHOT_DIR/${prefix}-${state}-${timestamp}.md"

  local content=$($CDP_CLI execute "window.__RECON_FULL__ = true; $(cat "$SCRIPT_DIR/js/html2md.js")")

  # Smart diff by default (unless --full specified)
  if [ "$FORCE_FULL" = false ]; then
    local latest=$(ls -t "$SNAPSHOT_DIR/${prefix}-${state}"-*.md 2>/dev/null | head -1)
    if [ -n "$latest" ]; then
      # Previous snapshot exists - show diff
      echo "$content" | tee "$snapshot_file" | diff "$latest" - || true
    else
      # No previous snapshot - show full
      echo "$content" | tee "$snapshot_file"
    fi
  else
    # Force full
    echo "$content" | tee "$snapshot_file"
  fi
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

  ensure_chrome_running || return 1

  # Extract domain from target URL
  local target_domain=$(echo "$URL" | python3 -c "
import sys
from urllib.parse import urlparse
url = sys.stdin.read().strip()
parsed = urlparse(url)
print(parsed.netloc)
")

  # Get current tab's domain (if exists)
  local current_domain=$($CDP_CLI execute "location.hostname" 2>/dev/null | tr -d '"' || echo "")

  # Smart domain-based tab reuse
  if [ -n "$current_domain" ] && [ "$current_domain" = "$target_domain" ]; then
    # Same domain → reuse tab (navigate in place)
    $CDP_CLI open "$URL" > /dev/null
  else
    # Different domain → create new tab
    curl -s -X PUT "http://$CDP_HOST:$CDP_PORT/json/new?$URL" > /dev/null
    sleep 0.5  # Brief wait for tab creation
  fi

  # Wait for page with general strategy (readyState + network + DOM)
  cmd_wait > /dev/null 2>&1

  # Show URL structure
  cmd_inspect

  # Show page content
  cmd_snapshot
}

# ============================================================================
# Command: wait
# ============================================================================
cmd_wait() {
  ensure_chrome_running || return 1

  local timeout=${CHROME_WAIT_TIMEOUT}
  local SELECTOR=""

  while [ $# -gt 0 ]; do
    case "$1" in
      -*) echo "Unknown option: $1" >&2; return 1 ;;
      *) SELECTOR="$1"; shift ;;
    esac
  done

  local interval=${CHROME_WAIT_INTERVAL}
  local elapsed=0

  if [ -n "$SELECTOR" ]; then
    # Wait for element to appear
    while (( $(echo "$elapsed < $timeout" | bc -l) )); do
      result=$($CDP_CLI execute "document.querySelector('$SELECTOR') ? 'found' : 'waiting'")
      if [ "$result" = "found" ]; then
        echo "OK: $SELECTOR found"
        return 0
      fi
      sleep $interval
      elapsed=$(echo "$elapsed + $interval" | bc)
    done
    echo "TIMEOUT: $SELECTOR not found after ${timeout}s" >&2
    return 1

  else
    # Unified smart wait: Check all conditions in one loop
    # Exits when: readyState complete AND network idle AND DOM stable
    # Or: 3 second timeout

    local max_wait=3
    local snapshot=""

    while (( $(echo "$elapsed < $max_wait" | bc -l) )); do
      sleep $interval
      elapsed=$(echo "$elapsed + $interval" | bc)

      # Check all three conditions
      ready_state=$($CDP_CLI execute "document.readyState" 2>/dev/null || echo "loading")
      active_requests=$($CDP_CLI execute "performance.getEntriesByType('resource').filter(r => !r.responseEnd).length" 2>/dev/null || echo "0")
      current_snapshot=$($CDP_CLI execute "document.body.innerHTML.length + '|' + document.querySelectorAll('*').length" 2>/dev/null || echo "0|0")

      # Condition 1: readyState complete
      ready_state_ok=false
      if [ "$ready_state" = "complete" ]; then
        ready_state_ok=true
      fi

      # Condition 2: Network idle
      network_idle=false
      if [ "$active_requests" = "0" ]; then
        network_idle=true
      fi

      # Condition 3: DOM stable (only check after first iteration)
      dom_stable=false
      if [ -n "$snapshot" ] && [ "$current_snapshot" = "$snapshot" ]; then
        dom_stable=true
      fi

      # Exit when ALL conditions are true
      if [ "$ready_state_ok" = true ] && [ "$network_idle" = true ] && [ "$dom_stable" = true ]; then
        echo "OK: Ready"
        return 0
      fi

      # Update snapshot for next iteration
      snapshot="$current_snapshot"
    done

    # Timeout: Content likely ready anyway
    echo "OK: Ready (timeout)"
    return 0
  fi
}

# ============================================================================
# Smart contextual wait - watches specific containers for changes
# ============================================================================
smart_wait_with_context() {
  local context_b64="$1"
  local timeout=3
  local interval=${CHROME_WAIT_INTERVAL}
  local elapsed=0

  # Decode context
  local context_json=$(echo "$context_b64" | python3 -c "import sys,json,base64; print(base64.b64decode(sys.stdin.read()).decode())" 2>/dev/null)

  # Extract selectors (prefer parent, fallback to grandparent)
  local parent_selector=$(echo "$context_json" | python3 -c "import sys,json; ctx=json.load(sys.stdin); p=ctx.get('parent'); print(p['selector'] if p and p.get('selector') else '')" 2>/dev/null)
  local parent_childCount=$(echo "$context_json" | python3 -c "import sys,json; ctx=json.load(sys.stdin); p=ctx.get('parent'); print(p['childCount'] if p else 0)" 2>/dev/null)
  local parent_innerHTML=$(echo "$context_json" | python3 -c "import sys,json; ctx=json.load(sys.stdin); p=ctx.get('parent'); print(p['innerHTML'] if p else 0)" 2>/dev/null)

  # If no valid parent selector, fall back to general wait
  if [ -z "$parent_selector" ] || [ "$parent_selector" = "null" ]; then
    cmd_wait > /dev/null 2>&1
    return 0
  fi

  # Build JS check for container stability
  local check_js="(function() {
    var container = document.querySelector('$parent_selector');
    if (!container) return 'gone';
    return container.children.length + '|' + container.innerHTML.length;
  })();"

  local snapshot="${parent_childCount}|${parent_innerHTML}"

  while (( $(echo "$elapsed < $timeout" | bc -l) )); do
    sleep $interval
    elapsed=$(echo "$elapsed + $interval" | bc)

    current_snapshot=$($CDP_CLI execute "$check_js" 2>/dev/null || echo "error")

    # Container disappeared (unusual but possible)
    if [ "$current_snapshot" = "gone" ] || [ "$current_snapshot" = "error" ]; then
      echo "OK: Context changed (container updated)" >&2
      return 0
    fi

    # Check if container is stable
    if [ "$current_snapshot" = "$snapshot" ]; then
      echo "OK: Context stable" >&2
      return 0
    fi

    # Update snapshot for next iteration
    snapshot="$current_snapshot"
  done

  # Timeout: assume content ready
  echo "OK: Context stable (timeout)" >&2
  return 0
}

# ============================================================================
# Command: interact
# ============================================================================
cmd_interact() {
  ensure_chrome_running || return 1

  local SELECTOR=""
  local INPUT_VALUE=""
  local INDEX=""

  # Parse arguments
  while [ $# -gt 0 ]; do
    case "$1" in
      --input)
        INPUT_VALUE="$2"
        shift 2
        ;;
      --index)
        INDEX="$2"
        shift 2
        ;;
      *)
        if [ -z "$SELECTOR" ]; then
          SELECTOR="$1"
          shift
        else
          echo "Unknown argument: $1" >&2
          return 1
        fi
        ;;
    esac
  done

  if [ -z "$SELECTOR" ]; then
    echo "Usage: interact 'selector or text' [--input 'value'] [--index N]" >&2
    return 1
  fi

  # Escape values for JavaScript
  SELECTOR_ESC=$(printf '%s' "$SELECTOR" | sed "s/'/\\\\'/g")

  # Build JavaScript in a temp file to avoid bash escaping issues
  local temp_js=$(mktemp)

  # Write variable definitions
  echo "var INTERACT_SELECTOR='$SELECTOR_ESC';" > "$temp_js"
  echo "var INTERACT_INPUT=undefined;" >> "$temp_js"
  echo "var INTERACT_INDEX=undefined;" >> "$temp_js"

  if [ -n "$INPUT_VALUE" ]; then
    VALUE_ESC=$(printf '%s' "$INPUT_VALUE" | sed "s/'/\\\\'/g")
    echo "INTERACT_INPUT='$VALUE_ESC';" >> "$temp_js"
  fi

  if [ -n "$INDEX" ]; then
    echo "INTERACT_INDEX=$INDEX;" >> "$temp_js"
  fi

  # Append interact.js content
  cat "$SCRIPT_DIR/js/interact.js" >> "$temp_js"

  # Execute and cleanup
  result=$($CDP_CLI execute "$(cat "$temp_js")")
  rm -f "$temp_js"

  # Parse JSON result
  status=$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','UNKNOWN'))" 2>/dev/null || echo "UNKNOWN")
  message=$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('message',''))" 2>/dev/null || echo "$result")
  context=$(echo "$result" | python3 -c "import sys,json; import base64; ctx=json.load(sys.stdin).get('context'); print(base64.b64encode(json.dumps(ctx).encode()).decode() if ctx else '')" 2>/dev/null || echo "")

  # Display message
  echo "$status: $message"

  # Handle error cases
  if [ "$status" = "FAIL" ] || [ "$status" = "ERROR" ]; then
    return 1
  fi

  # Show disambiguation without failing
  if [ "$status" = "DISAMBIGUATE" ]; then
    return 0
  fi

  # Auto-run wait and snapshot (only for successful interactions)
  if [ "$status" = "OK" ]; then
    # Tier 1: Smart contextual wait (if context available)
    if [ -n "$context" ]; then
      smart_wait_with_context "$context"
    # Tier 2: General fallback
    else
      cmd_wait > /dev/null 2>&1
    fi

    # Auto-snapshot (smart diff by default)
    cmd_snapshot
  fi
}

# ============================================================================
# Command: sendkey
# ============================================================================
cmd_sendkey() {
  local KEY=$1
  if [ -z "$KEY" ]; then
    echo "Usage: sendkey <key>" >&2
    echo "Supported keys: esc, enter, tab, space, backspace, delete, arrowup, arrowdown, arrowleft, arrowright, pageup, pagedown, home, end, f1-f12" >&2
    return 1
  fi

  ensure_chrome_running || return 1

  # Send key via JavaScript (pass key name as global variable)
  local js_code="var KEY_NAME = '$KEY'; $(cat "$SCRIPT_DIR/js/send-key.js")"
  local result=$($CDP_CLI execute "$js_code")
  local status=$(echo "$result" | grep -o "^OK\|^ERROR" || echo "ERROR")

  echo "$result"

  # Auto-run wait and snapshot (only for successful keystrokes)
  if [ "$status" = "OK" ]; then
    cmd_wait > /dev/null 2>&1
    cmd_snapshot
  fi
}

# ============================================================================
# Command: inspect
# ============================================================================
cmd_inspect() {
  ensure_chrome_running || return 1
  local result=$($CDP_CLI execute "$(cat "$SCRIPT_DIR/js/inspect.js")")
  echo "$result" | python3 "$SCRIPT_DIR/py/format-inspect.py"
}

# ============================================================================
# Command: execute
# ============================================================================
cmd_execute() {
  local JS_CODE=""
  local FROM_FILE=false

  while [ $# -gt 0 ]; do
    case "$1" in
      --file)
        FROM_FILE=true
        if [ -z "$2" ]; then
          echo "ERROR: --file requires a path argument" >&2
          return 1
        fi
        if [ ! -f "$2" ]; then
          echo "ERROR: File not found: $2" >&2
          return 1
        fi
        JS_CODE=$(cat "$2")
        shift 2
        ;;
      *)
        JS_CODE="$1"
        shift
        ;;
    esac
  done

  if [ -z "$JS_CODE" ]; then
    echo "Usage: execute <javascript>" >&2
    echo "       execute --file <path>" >&2
    return 1
  fi

  ensure_chrome_running || return 1

  # Execute JavaScript and show result
  local result=$($CDP_CLI execute "$JS_CODE" 2>&1)
  local exit_code=$?

  if [ $exit_code -ne 0 ]; then
    echo "$result" >&2
    return 1
  fi

  echo "$result"

  # Auto-run wait and snapshot (like interact/sendkey)
  cmd_wait > /dev/null 2>&1
  cmd_snapshot
}

# ============================================================================
# Command: tabs
# ============================================================================
get_tab_id_from_index() {
  local index=$1
  curl -s "http://$CDP_HOST:$CDP_PORT/json" | python3 -c "import sys,json; tabs=[t for t in json.load(sys.stdin) if t.get('type') == 'page']; print(tabs[$index]['id'] if $index < len(tabs) else '')" 2>/dev/null
}

cmd_tabs() {
  local subcommand="$1"

  ensure_chrome_running || return 1

  if [ -z "$subcommand" ]; then
    # List all tabs (default) - filter to only show page tabs
    local tabs_json=$(curl -s "http://$CDP_HOST:$CDP_PORT/json")
    echo "$tabs_json" | python3 -c "
import sys, json
all_tabs = json.load(sys.stdin)
tabs = [t for t in all_tabs if t.get('type') == 'page']
for i, tab in enumerate(tabs):
    url = tab.get('url', 'about:blank')
    title = tab.get('title', '(no title)')
    print(f'[{i}] {url}')
    if title and title != url:
        print(f'    {title}')
"
    return 0
  fi

  case "$subcommand" in
    activate)
      local index="$2"
      if [ -z "$index" ]; then
        echo "Usage: tabs activate <index>" >&2
        return 1
      fi

      local tab_id=$(get_tab_id_from_index "$index")
      if [ -z "$tab_id" ]; then
        echo "ERROR: Invalid tab index: $index" >&2
        return 1
      fi

      curl -s "http://$CDP_HOST:$CDP_PORT/json/activate/$tab_id" > /dev/null
      echo "OK: Activated tab $index"
      ;;

    close)
      local index="$2"
      if [ -z "$index" ]; then
        echo "Usage: tabs close <index>" >&2
        return 1
      fi

      local tab_id=$(get_tab_id_from_index "$index")
      if [ -z "$tab_id" ]; then
        echo "ERROR: Invalid tab index: $index" >&2
        return 1
      fi

      # Count page tabs to ensure we always have at least one
      local tab_count=$(curl -s "http://$CDP_HOST:$CDP_PORT/json" | python3 -c "import sys,json; print(len([t for t in json.load(sys.stdin) if t.get('type') == 'page']))")

      # If closing the last tab, create a new one first (like Chrome does)
      if [ "$tab_count" -eq 1 ]; then
        curl -s -X PUT "http://$CDP_HOST:$CDP_PORT/json/new?about:blank" > /dev/null
      fi

      curl -s -X DELETE "http://$CDP_HOST:$CDP_PORT/json/close/$tab_id" > /dev/null
      echo "OK: Closed tab $index"
      ;;

    *)
      echo "Unknown tabs subcommand: $subcommand" >&2
      echo "Usage: tabs                  List tabs" >&2
      echo "       tabs activate <index> Activate tab" >&2
      echo "       tabs close <index>    Close tab" >&2
      return 1
      ;;
  esac
}

# ============================================================================
# Command: screenshot (VISUAL)
# ============================================================================
cmd_screenshot() {
  ensure_chrome_running || return 1
  $CDP_CLI screenshot "$@"
}

# ============================================================================
# Command: pointer (VISUAL)
# ============================================================================
cmd_pointer() {
  local subcommand="$1"
  shift

  case "$subcommand" in
    click)
      ensure_chrome_running || return 1
      $CDP_CLI click "$@"
      ;;
    hover)
      ensure_chrome_running || return 1
      $CDP_CLI hover "$@"
      ;;
    drag)
      ensure_chrome_running || return 1
      $CDP_CLI drag "$@"
      ;;
    "")
      echo "Usage: pointer <click|hover|drag> <args...>" >&2
      echo "  click <x> <y>           - Click at coordinates" >&2
      echo "  hover <x> <y>           - Hover at coordinates" >&2
      echo "  drag <x1> <y1> <x2> <y2> - Drag from->to" >&2
      return 1
      ;;
    *)
      echo "Unknown pointer subcommand: $subcommand" >&2
      return 1
      ;;
  esac
}

# ============================================================================
# Command: profile
# ============================================================================
cmd_profile() {
  local subcommand="$1"

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
    echo "Profile renamed: $old_normalized -> $new_normalized"
    return 0
  fi

  # Default: open profile for login (always headed)
  local profile_name="$subcommand"
  local url="$2"

  local normalized=$(normalize_profile_name "$profile_name")
  local profile_path=$(expand_profile_path "$profile_name")

  mkdir -p "$profile_path"

  # Kill any existing Chrome on CDP port
  if cdp_is_running; then
    echo "Closing existing Chrome session..."
    cmd_close > /dev/null
    sleep 1
  fi

  echo "Opening profile '$normalized' for login..."
  if [ -n "$url" ]; then
    echo "Navigate to: $url"
  fi
  echo "Login as needed. Close the browser when done."
  echo ""

  # Launch headed Chrome for manual login
  if [ -n "$url" ]; then
    "$CHROME_APP" \
      --remote-debugging-port=$CDP_PORT \
      --user-data-dir="$profile_path" \
      --no-first-run \
      --no-default-browser-check \
      "$url"
  else
    "$CHROME_APP" \
      --remote-debugging-port=$CDP_PORT \
      --user-data-dir="$profile_path" \
      --no-first-run \
      --no-default-browser-check
  fi

  echo ""
  echo "Profile '$normalized' ready for use."
  echo "  Use: $TOOL_NAME --profile $normalized open URL"
}

# ============================================================================
# Command: help
# ============================================================================
cmd_help() {
  cat << EOF
$TOOL_NAME - Browser automation with CDP (Chrome DevTools Protocol)

Usage: $TOOL_NAME [OPTIONS] <command> [args...]

OPTIONS:
  --profile NAME    Use named profile (headless mode by default)
  --debug           Force headed mode even with --profile (for debugging)

MODES:
  Default           Headed Chrome (visible window)
  --profile NAME    Headless Chrome with saved credentials
  --profile --debug Headed Chrome with saved credentials

COMMANDS:
  Primary:
    open URL          Navigate to URL, discover structure, show content
    interact SELECTOR Click or input element, show results
      --input VALUE   Set input value instead of clicking
      --index N       Select Nth match when multiple elements found

  Secondary:
    profile [NAME]    Manage credential profiles for auth
      (no args)       List all profiles
      NAME [URL]      Open headed browser for login
      rename OLD NEW  Rename a profile
    tabs              List/activate/close tabs
      (no args)       List all tabs with index
      activate INDEX  Switch to tab
      close INDEX     Close tab

  Utility:
    snapshot          Capture page state (smart diff by default)
      --full          Show full snapshot instead of diff
    inspect           Discover URL parameters from links/forms
    wait [SEL]        Wait for DOM stability or element
    sendkey KEY       Send keyboard input (auto-runs wait and snapshot)
                      Supported: esc, enter, tab, space, backspace, delete,
                      arrowup/down/left/right, pageup/down, home, end, f1-f12
    execute JS        Execute JavaScript (auto-runs wait and snapshot)
      --file PATH     Execute from file
    tabs [CMD]        Manage Chrome tabs
      (no args)       List all tabs
      close INDEX     Close tab by index
      activate INDEX  Switch to tab by index

VISUAL COMMANDS (Vision-based automation):
  screenshot [OPTIONS]
                    Capture page screenshot for AI vision (~1,280 tokens)
    --width=N       Viewport width (default: 1200)
    --height=N      Viewport height (default: 800)
    --quality=N     JPEG quality 1-100 (default: 70)
    --full          Capture full page

  pointer click X Y
                    Click at pixel coordinates from screenshot
  pointer hover X Y
                    Hover at pixel coordinates
  pointer drag X1 Y1 X2 Y2
                    Drag from one coordinate to another

MANAGEMENT:
  profile [NAME]    Manage credential profiles
    (no args)       List all profiles
    NAME [URL]      Open headed browser for login
    rename OLD NEW  Rename a profile

  help              Show this help

PROFILE WORKFLOW:
  1. Create profile (login manually):
     $TOOL_NAME profile work https://mail.google.com

  2. Use profile (headless automation):
     $TOOL_NAME --profile work open https://mail.google.com

  3. Debug profile issues (headed):
     $TOOL_NAME --profile work --debug open https://mail.google.com

EXAMPLES:
  # Standard automation
  $TOOL_NAME open "https://example.com"
  $TOOL_NAME interact "Submit"
  $TOOL_NAME interact "#email" --input "user@example.com"
  $TOOL_NAME interact "Load More"
  $TOOL_NAME tabs
  $TOOL_NAME tabs close 0
  $TOOL_NAME execute "document.title"
  $TOOL_NAME sendkey esc

  # Vision-based automation (no CSS selectors needed!)
  $TOOL_NAME screenshot              # AI sees page, identifies coordinates
  $TOOL_NAME pointer click 600 130   # Click button at those coordinates

  # Profile automation
  $TOOL_NAME --profile personal open "https://gmail.com"

PERSISTENCE:
  Chrome stays running between commands. Use 'tabs close' to close individual tabs.
  Each profile maintains separate cookies/sessions.

EOF
}

# ============================================================================
# Execute single command
# ============================================================================
execute_single() {
  local cmd="$1"
  shift
  case "$cmd" in
    snapshot)   cmd_snapshot "$@" ;;
    inspect)    cmd_inspect "$@" ;;
    open)       cmd_open "$@" ;;
    wait)       cmd_wait "$@" ;;
    interact)   cmd_interact "$@" ;;
    sendkey)    cmd_sendkey "$@" ;;
    tabs)       cmd_tabs "$@" ;;
    execute)    cmd_execute "$@" ;;
    esc)        cmd_esc "$@" ;;
    screenshot) cmd_screenshot "$@" ;;
    pointer)    cmd_pointer "$@" ;;
    profile)    cmd_profile "$@" ;;
    help|--help|-h) cmd_help ;;
    *)
      echo "Unknown command: $cmd" >&2
      return 1
      ;;
  esac
}

# ============================================================================
# Main execution
# ============================================================================

# Execute single command
case "$1" in
  snapshot|inspect|open|wait|interact|sendkey|tabs|execute|esc|screenshot|pointer|profile)
    cmd="$1"
    shift
    execute_single "$cmd" "$@"
    ;;
  help|--help|-h|"")
    cmd_help
    ;;
  *)
    echo "Unknown command: $1" >&2
    echo "Run '$TOOL_NAME help' for usage" >&2
    exit 1
    ;;
esac
