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

# Profile locations - profiles stored in tool directory
PROFILES_DIR="$SCRIPT_DIR/profiles"
DATA_DIR="$SCRIPT_DIR/data"
DEFAULT_PROFILE="$DATA_DIR/default"

# Export for cdp-cli.js
export CDP_PORT CDP_HOST

# ============================================================================
# Profile utilities
# ============================================================================

# Normalize profile name: lowercase, underscores, alphanumeric only
normalize_profile_name() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/_/g' | tr -s '_'
}

# Expand profile name to full path
expand_profile_path() {
  local profile="$1"
  if [[ "$profile" == /* ]] || [[ "$profile" == ~* ]]; then
    echo "$profile"
  else
    local normalized=$(normalize_profile_name "$profile")
    echo "$PROFILES_DIR/$normalized"
  fi
}

# Get service name from URL using domain mappings
get_service_name() {
  local url="$1"
  local domain=$(echo "$url" | sed -E 's|https?://([^/]+).*|\1|')

  # Check domain mappings file
  local mappings="$SCRIPT_DIR/domain-mappings.json"
  if [ -f "$mappings" ]; then
    local service=$(jq -r ".[\"$domain\"] // empty" "$mappings" 2>/dev/null)
    if [ -n "$service" ]; then
      echo "$service"
      return 0
    fi
  fi

  # Fallback: strip TLD and normalize
  local service=$(echo "$domain" | sed -E 's/^www\.//; s/\.(com|co\.uk|de|ca|fr|jp|org|net|io|app|dev)$//' | tr '.' '-')
  echo "$service"
}

# Write profile metadata JSON
write_profile_metadata() {
  local profile_path="$1"
  local service="$2"
  local account="$3"
  local source="$4"
  local source_type="$5"
  local source_path="${6:-}"

  local meta_file="$profile_path/.profile-meta.json"
  local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  cat > "$meta_file" << EOF
{
  "display": "<$service> $account ($source)",
  "service": "$service",
  "account": "$account",
  "source": "$source",
  "source_type": "$source_type",
  "source_path": "$source_path",
  "created": "$now",
  "last_used": "$now",
  "status": "enabled"
}
EOF
}

# Read specific field from profile metadata
read_profile_metadata() {
  local profile_path="$1"
  local field="$2"
  local meta_file="$profile_path/.profile-meta.json"

  if [ ! -f "$meta_file" ]; then
    return 1
  fi

  jq -r ".$field // empty" "$meta_file" 2>/dev/null
}

# Update metadata field
update_profile_metadata() {
  local profile_path="$1"
  local field="$2"
  local value="$3"
  local meta_file="$profile_path/.profile-meta.json"

  if [ ! -f "$meta_file" ]; then
    return 1
  fi

  local tmp_file=$(mktemp)
  jq ".$field = \"$value\"" "$meta_file" > "$tmp_file" && mv "$tmp_file" "$meta_file"
}

# Find profiles matching search string (fuzzy match)
fuzzy_match_profile() {
  local search="$1"
  local matches=()

  if [ ! -d "$PROFILES_DIR" ]; then
    return 1
  fi

  local search_normalized=$(echo "$search" | tr '[:upper:]' '[:lower:]')

  for dir in "$PROFILES_DIR"/*; do
    if [ ! -d "$dir" ]; then
      continue
    fi

    local basename=$(basename "$dir")
    local basename_lower=$(echo "$basename" | tr '[:upper:]' '[:lower:]')

    if [[ "$basename_lower" == *"$search_normalized"* ]]; then
      matches+=("$basename")
    fi
  done

  if [ ${#matches[@]} -eq 0 ]; then
    return 1
  fi

  printf '%s\n' "${matches[@]}"
  return 0
}

# Interactive fuzzy match selection
prompt_fuzzy_match() {
  local search="$1"
  local matches=()

  while IFS= read -r match; do
    matches+=("$match")
  done < <(fuzzy_match_profile "$search")

  if [ ${#matches[@]} -eq 0 ]; then
    return 1
  fi

  echo "" >&2
  echo "Profile '$search' not found." >&2
  echo "" >&2
  echo "Did you mean:" >&2

  local i=1
  for match in "${matches[@]}"; do
    local display=$(read_profile_metadata "$PROFILES_DIR/$match" "display")
    if [ -n "$display" ]; then
      echo "  [$i] $display" >&2
    else
      echo "  [$i] $match" >&2
    fi
    i=$((i + 1))
  done
  echo "" >&2

  echo -n "Select [1-${#matches[@]}] or Ctrl+C to cancel: " >&2
  read selection

  if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt ${#matches[@]} ]; then
    echo "Invalid selection" >&2
    return 1
  fi

  echo "${matches[$((selection - 1))]}"
  return 0
}

# ============================================================================
# Chrome.app import helpers
# ============================================================================

# Get all Chrome.app profiles
get_chrome_app_profiles() {
  local chrome_dir="$HOME/Library/Application Support/Google/Chrome"
  if [ ! -d "$chrome_dir" ]; then
    return 1
  fi

  # Find all profile directories (Default, Profile 1, Profile 2, etc.)
  for dir in "$chrome_dir"/*/; do
    if [ -d "$dir" ]; then
      local basename=$(basename "$dir")
      if [[ "$basename" == "Default" ]] || [[ "$basename" =~ ^Profile\ [0-9]+$ ]]; then
        echo "$dir"
      fi
    fi
  done
  return 0
}

# Format time ago (seconds to human readable)
format_time_ago() {
  local seconds=$1

  if [ $seconds -lt 60 ]; then
    echo "just now"
  elif [ $seconds -lt 3600 ]; then
    local mins=$((seconds / 60))
    echo "${mins}m ago"
  elif [ $seconds -lt 86400 ]; then
    local hours=$((seconds / 3600))
    echo "${hours}h ago"
  else
    local days=$((seconds / 86400))
    echo "${days}d ago"
  fi
}

# Detect active accounts from Chrome.app profile
# Output format: domain|last_access_time|visit_count
detect_chrome_accounts() {
  local profile_path="$1"
  local target_service="$2"  # Service name to filter by (gmail, amazon, etc.)

  local cookies_db="$profile_path/Cookies"
  local history_db="$profile_path/History"

  if [ ! -f "$cookies_db" ]; then
    return 1
  fi

  # Get current time in Chrome's time format (microseconds since 1601-01-01)
  local now_chrome=$(python3 -c "from datetime import datetime; epoch_1601 = datetime(1601, 1, 1); now = datetime.now(); print(int((now - epoch_1601).total_seconds() * 1000000))")

  # Seven days ago in Chrome time
  local seven_days_ago=$((now_chrome - 7 * 24 * 60 * 60 * 1000000))

  # Query cookies for target service domains
  # Filter to unexpired cookies accessed in last 7 days or most recent
  local cookie_query="
    SELECT DISTINCT host_key, MAX(last_access_utc) as last_access
    FROM cookies
    WHERE expires_utc > $now_chrome
      AND last_access_utc > 0
    GROUP BY host_key
    ORDER BY last_access DESC
  "

  # Get domains with cookies
  local domains=()
  local seen_domains=()  # Track already seen domains to avoid duplicates

  while IFS='|' read -r domain last_access; do
    # Strip leading dot from domain
    domain=$(echo "$domain" | sed 's/^\.//')

    # Check for duplicate domain AFTER normalization (skip if already seen)
    local already_seen=false
    for seen in "${seen_domains[@]}"; do
      if [ "$seen" = "$domain" ]; then
        already_seen=true
        break
      fi
    done

    if [ "$already_seen" = true ]; then
      continue
    fi

    # Mark domain as seen
    seen_domains+=("$domain")

    # Check if domain matches target service using domain-mappings.json
    local mappings="$SCRIPT_DIR/domain-mappings.json"
    local service=""
    if [ -f "$mappings" ]; then
      service=$(jq -r ".[\"$domain\"] // empty" "$mappings" 2>/dev/null)
    fi

    # If no mapping, try TLD stripping fallback
    if [ -z "$service" ]; then
      service=$(echo "$domain" | sed -E 's/^www\.//; s/\.(com|co\.uk|de|ca|fr|jp|org|net|io|app|dev)$//' | tr '.' '-')
    fi

    # Skip if not matching target service
    if [ "$service" != "$target_service" ]; then
      continue
    fi

    # Get visit count from History database
    local visit_count=0
    if [ -f "$history_db" ]; then
      visit_count=$(sqlite3 "$history_db" "
        SELECT COUNT(*)
        FROM urls
        WHERE url LIKE '%://%$domain%'
        " 2>/dev/null || echo "0")
    fi

    # Calculate seconds ago
    local seconds_ago=$(python3 -c "print(int(($now_chrome - $last_access) / 1000000))")

    # Only include if accessed in last 7 days OR most recent
    if [ $last_access -gt $seven_days_ago ] || [ ${#domains[@]} -eq 0 ]; then
      domains+=("$domain|$seconds_ago|$visit_count")
    fi
  done < <(sqlite3 "$cookies_db" "$cookie_query" 2>/dev/null)

  if [ ${#domains[@]} -eq 0 ]; then
    return 1
  fi

  printf '%s\n' "${domains[@]}"
  return 0
}

# ============================================================================
# Port registry and profile locking
# ============================================================================

# Port registry file location
PORT_REGISTRY="$DATA_DIR/port-registry"

# Initialize registry directory
init_registry() {
  mkdir -p "$(dirname "$PORT_REGISTRY")"
  touch "$PORT_REGISTRY"
}

# Get deterministic port for profile (based on name hash)
# Returns: port number in range 9222-9299
get_profile_port() {
  local profile="$1"
  local hash=$(echo -n "$profile" | cksum | cut -d' ' -f1)
  local port=$((9222 + hash % 78))
  echo "$port"
}

# Check if a profile is currently in use
# Returns: 0 if in use, 1 if available
# Sets: EXISTING_PORT, EXISTING_PID, EXISTING_START_TIME
is_profile_in_use() {
  local profile="$1"
  init_registry

  # Check registry for this profile
  local entry=$(grep "^$profile:" "$PORT_REGISTRY" 2>/dev/null | head -1)
  if [ -z "$entry" ]; then
    return 1  # Not in registry = available
  fi

  # Parse entry: profile:port:pid:start_time
  EXISTING_PORT=$(echo "$entry" | cut -d: -f2)
  EXISTING_PID=$(echo "$entry" | cut -d: -f3)
  EXISTING_START_TIME=$(echo "$entry" | cut -d: -f4)

  # Verify process is still running
  if ! ps -p "$EXISTING_PID" > /dev/null 2>&1; then
    # Stale entry, clean it up
    sed -i '' "/^$profile:/d" "$PORT_REGISTRY" 2>/dev/null || true
    return 1  # Available
  fi

  # Verify Chrome is actually listening on that port
  if ! lsof -i ":$EXISTING_PORT" -sTCP:LISTEN > /dev/null 2>&1; then
    # Process exists but Chrome not running, clean up
    sed -i '' "/^$profile:/d" "$PORT_REGISTRY" 2>/dev/null || true
    return 1  # Available
  fi

  return 0  # In use
}

# Assign port for profile (with locking)
# Returns: port number on success, exits with error if profile locked
assign_port_for_profile() {
  local profile="$1"
  init_registry

  # Check if profile is already in use
  if is_profile_in_use "$profile"; then
    # Calculate how long ago it started
    local now=$(date +%s)
    local elapsed=$((now - EXISTING_START_TIME))
    local elapsed_min=$((elapsed / 60))
    local elapsed_sec=$((elapsed % 60))

    # Show error message
    echo "" >&2
    echo "ERROR: Profile '$profile' is already in use" >&2
    echo "" >&2
    echo "Details:" >&2
    echo "  Process ID: $EXISTING_PID" >&2
    echo "  CDP Port: $EXISTING_PORT" >&2
    if [ $elapsed_min -gt 0 ]; then
      echo "  Running for: ${elapsed_min}m ${elapsed_sec}s" >&2
    else
      echo "  Running for: ${elapsed_sec}s" >&2
    fi
    echo "" >&2

    return 1
  fi

  # Profile is available, find a port
  # First, check if this profile had a previous port assignment (reuse it)
  local preferred_port=$(get_profile_port "$profile")

  # Check if preferred port is available
  if ! grep -q ":$preferred_port:" "$PORT_REGISTRY" 2>/dev/null; then
    if ! lsof -i ":$preferred_port" -sTCP:LISTEN > /dev/null 2>&1; then
      # Preferred port is free, use it
      local start_time=$(date +%s)
      echo "$profile:$preferred_port:$$:$start_time" >> "$PORT_REGISTRY"
      echo "$preferred_port"
      return 0
    fi
  fi

  # Preferred port taken, find next available
  for port in $(seq 9222 9299); do
    # Skip if in registry
    if grep -q ":$port:" "$PORT_REGISTRY" 2>/dev/null; then
      continue
    fi

    # Skip if port in use by something else
    if lsof -i ":$port" -sTCP:LISTEN > /dev/null 2>&1; then
      continue
    fi

    # Port is available!
    local start_time=$(date +%s)
    echo "$profile:$port:$$:$start_time" >> "$PORT_REGISTRY"
    echo "$port"
    return 0
  done

  # No ports available (all 78 ports in use!)
  echo "" >&2
  echo "ERROR: No available CDP ports (9222-9299 all in use)" >&2
  echo "" >&2
  echo "Currently active profiles:" >&2
  cat "$PORT_REGISTRY" | while IFS=: read prof port pid start; do
    if ps -p "$pid" > /dev/null 2>&1; then
      echo "  $prof (port $port, PID $pid)" >&2
    fi
  done >&2
  echo "" >&2
  echo "Please close some Chrome instances and try again." >&2
  echo "" >&2

  return 1
}

# Release profile (cleanup registry entry)
release_profile() {
  local profile="$1"
  init_registry
  sed -i '' "/^$profile:/d" "$PORT_REGISTRY" 2>/dev/null || true
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
  # Profile locking: Assign port FIRST if using a named profile
  # This must happen before cdp_is_running() check to use the correct port
  if [ -n "$PROFILE" ]; then
    local assigned_port=$(assign_port_for_profile "$PROFILE")
    if [ $? -ne 0 ]; then
      # Profile is locked, error already displayed by assign_port_for_profile
      return 1
    fi
    CDP_PORT=$assigned_port
    export CDP_PORT  # Re-export so child processes see the new port
  fi

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
# Smart Dispatch Helpers
# ============================================================================

is_coordinates() {
  local arg1="$1"
  local arg2="$2"
  local arg3="$3"
  local arg4="$4"

  # Two numeric args (click/hover)
  if [[ "$arg1" =~ ^[0-9]+$ ]] && [[ "$arg2" =~ ^[0-9]+$ ]] && [ -z "$arg3" ]; then
    return 0
  fi

  # Four numeric args (drag)
  if [[ "$arg1" =~ ^[0-9]+$ ]] && [[ "$arg2" =~ ^[0-9]+$ ]] && \
     [[ "$arg3" =~ ^[0-9]+$ ]] && [[ "$arg4" =~ ^[0-9]+$ ]]; then
    return 0
  fi

  return 1
}

capture_viewport_context() {
  # Capture viewport state before coordinate interaction
  local result=$($CDP_CLI execute "JSON.stringify({
    scroll: {x: window.scrollX, y: window.scrollY},
    viewport: {width: window.innerWidth, height: window.innerHeight},
    hash: document.body.innerHTML.length
  })" 2>/dev/null)

  if [ $? -eq 0 ] && [ -n "$result" ]; then
    echo "$result" | python3 -c "import sys,json,base64; data=sys.stdin.read().strip(); print(base64.b64encode(data.encode()).decode())" 2>/dev/null
  fi
}

smart_wait_viewport() {
  local context_b64="$1"

  if [ -z "$context_b64" ]; then
    cmd_wait > /dev/null 2>&1
    return
  fi

  # Decode context and extract hash
  local prev_hash=$(echo "$context_b64" | python3 -c "
import sys, json, base64
try:
    data = base64.b64decode(sys.stdin.read().strip()).decode()
    obj = json.loads(data)
    print(obj.get('hash', 0))
except:
    print(0)
" 2>/dev/null)

  if [ -z "$prev_hash" ] || [ "$prev_hash" = "0" ]; then
    cmd_wait > /dev/null 2>&1
    return
  fi

  # Wait for viewport to change
  local max_wait=30
  local count=0

  while [ $count -lt $max_wait ]; do
    sleep 0.1
    count=$((count + 1))

    local current_hash=$($CDP_CLI execute "document.body.innerHTML.length" 2>/dev/null || echo "0")

    if [ "$current_hash" != "$prev_hash" ]; then
      cmd_wait > /dev/null 2>&1
      return 0
    fi
  done

  cmd_wait > /dev/null 2>&1
}

# ============================================================================
# Command: click
# ============================================================================
cmd_click() {
  ensure_chrome_running || return 1

  # Smart dispatch: coordinates vs selector
  if is_coordinates "$@"; then
    cmd_click_coordinates "$@"
  else
    cmd_click_selector "$@"
  fi
}

cmd_click_coordinates() {
  local x=$1
  local y=$2

  # Capture context before click
  local context_before=$(capture_viewport_context)

  # Perform click via CDP
  local result=$($CDP_CLI click "$x" "$y")
  local exit_code=$?

  echo "$result"

  if [ $exit_code -eq 0 ]; then
    # Auto-feedback
    smart_wait_viewport "$context_before"
    cmd_snapshot
  fi

  return $exit_code
}

cmd_click_selector() {
  # Reuse interact.js logic
  local SELECTOR=""
  local INDEX=""

  # Parse arguments
  while [ $# -gt 0 ]; do
    case "$1" in
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
    echo "Usage: click 'selector or text' [--index N]" >&2
    echo "       click X Y (coordinates)" >&2
    return 1
  fi

  # Escape for JavaScript
  SELECTOR_ESC=$(printf '%s' "$SELECTOR" | sed "s/'/\\\\'/g")

  # Build JavaScript
  local temp_js=$(mktemp)
  echo "var INTERACT_SELECTOR='$SELECTOR_ESC';" > "$temp_js"
  echo "var INTERACT_INPUT=undefined;" >> "$temp_js"
  echo "var INTERACT_INDEX=undefined;" >> "$temp_js"

  if [ -n "$INDEX" ]; then
    echo "INTERACT_INDEX=$INDEX;" >> "$temp_js"
  fi

  # Append interact.js (reuse existing logic)
  cat "$SCRIPT_DIR/js/interact.js" >> "$temp_js"

  # Execute
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

  # Auto-feedback (only for successful clicks)
  if [ "$status" = "OK" ]; then
    if [ -n "$context" ]; then
      smart_wait_with_context "$context"
    else
      cmd_wait > /dev/null 2>&1
    fi
    cmd_snapshot
  fi
}

# ============================================================================
# Command: input
# ============================================================================
cmd_input() {
  ensure_chrome_running || return 1

  local SELECTOR=""
  local VALUE=""
  local INDEX=""

  # Check for coordinates (not supported)
  if is_coordinates "$@"; then
    echo "Error: input requires a selector, coordinates not supported" >&2
    echo "Usage: input 'selector or text' 'value' [--index N]" >&2
    return 1
  fi

  # Parse arguments
  while [ $# -gt 0 ]; do
    case "$1" in
      --index)
        INDEX="$2"
        shift 2
        ;;
      *)
        if [ -z "$SELECTOR" ]; then
          SELECTOR="$1"
          shift
        elif [ -z "$VALUE" ]; then
          VALUE="$1"
          shift
        else
          echo "Unknown argument: $1" >&2
          return 1
        fi
        ;;
    esac
  done

  if [ -z "$SELECTOR" ] || [ -z "$VALUE" ]; then
    echo "Usage: input 'selector or text' 'value' [--index N]" >&2
    return 1
  fi

  # Escape for JavaScript
  SELECTOR_ESC=$(printf '%s' "$SELECTOR" | sed "s/'/\\\\'/g")
  VALUE_ESC=$(printf '%s' "$VALUE" | sed "s/'/\\\\'/g")

  # Build JavaScript
  local temp_js=$(mktemp)
  echo "var INTERACT_SELECTOR='$SELECTOR_ESC';" > "$temp_js"
  echo "var INTERACT_INPUT='$VALUE_ESC';" >> "$temp_js"
  echo "var INTERACT_INDEX=undefined;" >> "$temp_js"

  if [ -n "$INDEX" ]; then
    echo "INTERACT_INDEX=$INDEX;" >> "$temp_js"
  fi

  # Append interact.js
  cat "$SCRIPT_DIR/js/interact.js" >> "$temp_js"

  # Execute
  result=$($CDP_CLI execute "$(cat "$temp_js")")
  rm -f "$temp_js"

  # Parse and handle result (same as click_selector)
  status=$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','UNKNOWN'))" 2>/dev/null || echo "UNKNOWN")
  message=$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('message',''))" 2>/dev/null || echo "$result")
  context=$(echo "$result" | python3 -c "import sys,json; import base64; ctx=json.load(sys.stdin).get('context'); print(base64.b64encode(json.dumps(ctx).encode()).decode() if ctx else '')" 2>/dev/null || echo "")

  echo "$status: $message"

  if [ "$status" = "FAIL" ] || [ "$status" = "ERROR" ]; then
    return 1
  fi

  if [ "$status" = "DISAMBIGUATE" ]; then
    return 0
  fi

  if [ "$status" = "OK" ]; then
    if [ -n "$context" ]; then
      smart_wait_with_context "$context"
    else
      cmd_wait > /dev/null 2>&1
    fi
    cmd_snapshot
  fi
}

# ============================================================================
# Command: hover
# ============================================================================
cmd_hover() {
  ensure_chrome_running || return 1

  # Smart dispatch: coordinates vs selector
  if is_coordinates "$@"; then
    cmd_hover_coordinates "$@"
  else
    # Selector mode not fully implemented yet
    echo "Note: Hover by selector not fully implemented yet. Use coordinates: hover X Y" >&2
    return 1
  fi
}

cmd_hover_coordinates() {
  local x=$1
  local y=$2

  # Capture context before hover
  local context_before=$(capture_viewport_context)

  # Perform hover via CDP
  local result=$($CDP_CLI hover "$x" "$y")
  local exit_code=$?

  echo "$result"

  if [ $exit_code -eq 0 ]; then
    # Auto-feedback
    smart_wait_viewport "$context_before"
    cmd_snapshot
  fi

  return $exit_code
}

# ============================================================================
# Command: drag
# ============================================================================
cmd_drag() {
  ensure_chrome_running || return 1

  # Only coordinates supported initially
  if ! is_coordinates "$@"; then
    echo "Error: drag requires 4 coordinates (x1 y1 x2 y2)" >&2
    echo "Usage: drag X1 Y1 X2 Y2" >&2
    return 1
  fi

  local x1=$1
  local y1=$2
  local x2=$3
  local y2=$4

  # Capture context before drag
  local context_before=$(capture_viewport_context)

  # Perform drag via CDP
  local result=$($CDP_CLI drag "$x1" "$y1" "$x2" "$y2")
  local exit_code=$?

  echo "$result"

  if [ $exit_code -eq 0 ]; then
    # Auto-feedback
    smart_wait_viewport "$context_before"
    cmd_snapshot
  fi

  return $exit_code
}

# ============================================================================
# Command: interact (DEPRECATED - use click or input)
# ============================================================================
cmd_interact() {
  echo "⚠ Warning: 'interact' is deprecated. Use 'click' or 'input' instead." >&2

  # Detect --input flag and route appropriately
  local has_input_flag=0
  for arg in "$@"; do
    if [ "$arg" = "--input" ]; then
      has_input_flag=1
      break
    fi
  done

  if [ $has_input_flag -eq 1 ]; then
    # Convert: interact "selector" --input "value" → input "selector" "value"
    local selector=""
    local value=""
    local index=""

    while [ $# -gt 0 ]; do
      case "$1" in
        --input)
          value="$2"
          shift 2
          ;;
        --index)
          index="$2"
          shift 2
          ;;
        *)
          selector="$1"
          shift
          ;;
      esac
    done

    if [ -n "$index" ]; then
      cmd_input "$selector" "$value" --index "$index"
    else
      cmd_input "$selector" "$value"
    fi
  else
    # Forward to click
    cmd_click "$@"
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
  shift

  # Default: list profiles
  if [ -z "$subcommand" ]; then
    subcommand="list"
  fi

  case "$subcommand" in
    list)
      if [ ! -d "$PROFILES_DIR" ] || [ -z "$(ls -A "$PROFILES_DIR" 2>/dev/null)" ]; then
        echo "No profiles found"
        echo ""
        echo "Create a profile:"
        echo "  $TOOL_NAME profile create URL"
        echo ""
        echo "Import from Chrome.app:"
        echo "  $TOOL_NAME profile import URL"
        return 0
      fi

      echo "Profiles:"
      echo ""

      for dir in "$PROFILES_DIR"/*; do
        if [ ! -d "$dir" ]; then
          continue
        fi

        local basename=$(basename "$dir")
        local display=$(read_profile_metadata "$dir" "display")
        local status=$(read_profile_metadata "$dir" "status")

        if [ -n "$display" ]; then
          if [ "$status" = "disabled" ]; then
            echo "  $display [DISABLED]"
          else
            echo "  $display"
          fi
          echo "    Filename: $basename"
        else
          # No metadata - old profile format
          echo "  $basename (no metadata)"
        fi
        echo ""
      done
      ;;

    create)
      local url="$1"
      if [ -z "$url" ]; then
        echo "Usage: profile create URL" >&2
        echo "" >&2
        echo "Example:" >&2
        echo "  $TOOL_NAME profile create https://mail.google.com" >&2
        return 1
      fi

      local service=$(get_service_name "$url")

      echo "Creating profile for <$service>..."
      echo ""

      # Show existing profiles for this service
      if [ -d "$PROFILES_DIR" ]; then
        local service_profiles=()
        for dir in "$PROFILES_DIR"/*; do
          if [ -d "$dir" ]; then
            local prof_service=$(read_profile_metadata "$dir" "service")
            if [ "$prof_service" = "$service" ]; then
              local prof_account=$(read_profile_metadata "$dir" "account")
              if [ -n "$prof_account" ]; then
                service_profiles+=("$prof_account")
              fi
            fi
          fi
        done

        if [ ${#service_profiles[@]} -gt 0 ]; then
          echo "Existing <$service> profiles:"
          for acc in "${service_profiles[@]}"; do
            echo "  - $acc"
          done
          echo ""
        fi
      fi

      echo -n "Account identifier (email/username): "
      read account

      if [ -z "$account" ]; then
        echo "Error: Account identifier cannot be empty" >&2
        return 1
      fi

      local normalized_account=$(echo "$account" | tr '[:upper:]' '[:lower:]' | tr -s ' @.:-' '_' | sed 's/[^a-z0-9_]//g')
      local profile_name="${service}-${normalized_account}"
      local profile_path="$PROFILES_DIR/$profile_name"

      if [ -d "$profile_path" ]; then
        echo "Error: Profile '$profile_name' already exists" >&2
        return 1
      fi

      mkdir -p "$profile_path/Default"

      # Kill any existing Chrome on CDP port
      if cdp_is_running; then
        echo "Closing existing Chrome session..."
        cmd_close > /dev/null
        sleep 1
      fi

      echo ""
      echo "Opening headed browser for login..."
      echo "Login as: $account"
      echo "Close the browser when done."
      echo ""

      "$CHROME_APP" \
        --remote-debugging-port=$CDP_PORT \
        --user-data-dir="$profile_path" \
        --no-first-run \
        --no-default-browser-check \
        "$url"

      write_profile_metadata "$profile_path" "$service" "$account" "manual" "manual"

      echo ""
      echo "✓ Profile created: <$service> $account (manual)"
      echo "  Filename: $profile_name"
      echo ""
      echo "Use with:"
      echo "  $TOOL_NAME --profile $profile_name open URL"
      ;;

    import)
      local url="$1"
      local chrome_dir="$HOME/Library/Application Support/Google/Chrome"

      # Check if Chrome.app is installed
      if [ ! -d "$chrome_dir/Default" ]; then
        echo ""
        echo "ERROR: Chrome.app Default profile not found" >&2
        echo ""
        echo "Chrome.app must be installed and used at least once" >&2
        echo "before profile import can work." >&2
        echo ""
        return 1
      fi

      # Mode 1: Import ALL (discovery only - no URL provided)
      if [ -z "$url" ]; then
        local target_services=()
        local mappings="$SCRIPT_DIR/domain-mappings.json"

        echo ""
        echo "Scanning Chrome.app for all available accounts..."
        echo ""

        while IFS= read -r service; do
          target_services+=("$service")
        done < <(jq -r '.[] | select(. != null)' "$mappings" 2>/dev/null | sort -u)

        # Scan Chrome.app Default profile for each service
        local found_any=false
        local seen_services=()  # Track services we've shown to avoid duplicates

        for service in "${target_services[@]}"; do
          # Skip if we've already shown this service (deduplication)
          local already_shown=false
          for seen in "${seen_services[@]}"; do
            if [ "$seen" = "$service" ]; then
              already_shown=true
              break
            fi
          done

          if [ "$already_shown" = true ]; then
            continue
          fi

          # Detect accounts for this service
          local accounts=$(detect_chrome_accounts "$chrome_dir/Default" "$service")

          if [ -n "$accounts" ]; then
            found_any=true
            seen_services+=("$service")

            # Count accounts
            local count=$(echo "$accounts" | wc -l | tr -d ' ')

            echo "Found $count account(s) for <$service>:"

            # Show each account with time and visit info
            while IFS='|' read -r domain seconds_ago visit_count; do
              local time_str=$(format_time_ago "$seconds_ago")
              echo "  - $domain ($time_str, $visit_count visits)"
            done <<< "$accounts"

            echo ""
          fi
        done

        if [ "$found_any" = false ]; then
          echo "No accounts found in Chrome.app Default profile."
          echo ""
          echo "Make sure you're logged into services in Chrome.app first,"
          echo "then try importing again."
          echo ""
          return 1
        fi

        echo ""
        echo "Next steps:"
        echo "  Use 'profile import URL' to import credentials for a specific service."
        echo "  Example: profile import https://github.com"
        echo ""
        return 0
      fi

      # Mode 2: Import specific service with full cookie copy
      local service=$(get_service_name "$url")

      echo "Scanning Chrome.app profiles for <$service> accounts..."
      echo ""

      # Get all Chrome.app profiles
      local chrome_profiles=()
      while IFS= read -r profile_path; do
        chrome_profiles+=("$profile_path")
      done < <(get_chrome_app_profiles)

      if [ ${#chrome_profiles[@]} -eq 0 ]; then
        echo "Error: No Chrome.app profiles found" >&2
        echo "" >&2
        echo "Chrome.app profile directory not found at:" >&2
        echo "  $HOME/Library/Application Support/Google/Chrome" >&2
        return 1
      fi

      # Scan all profiles for accounts matching this service
      local accounts_by_profile=()
      local profile_names=()

      for chrome_profile in "${chrome_profiles[@]}"; do
        local profile_name=$(basename "$chrome_profile")
        local accounts=()

        # Detect accounts for this service in this Chrome.app profile
        while IFS='|' read -r domain seconds_ago visit_count; do
          accounts+=("$domain|$seconds_ago|$visit_count")
        done < <(detect_chrome_accounts "$chrome_profile" "$service")

        # Only include profiles with accounts
        if [ ${#accounts[@]} -gt 0 ]; then
          profile_names+=("$profile_name")
          accounts_by_profile+=("$(IFS=$'\n'; echo "${accounts[*]}")")
        fi
      done

      if [ ${#profile_names[@]} -eq 0 ]; then
        echo "No <$service> accounts found in Chrome.app profiles" >&2
        echo "" >&2
        echo "Make sure you're logged into $service in Chrome.app first" >&2
        return 1
      fi

      # Display profiles and accounts
      local option_num=1
      local option_to_profile=()
      local option_to_account=()

      for i in "${!profile_names[@]}"; do
        echo "Profile: ${profile_names[$i]}"

        # Split accounts for this profile
        local accounts_str="${accounts_by_profile[$i]}"
        while IFS='|' read -r domain seconds_ago visit_count; do
          local time_str=$(format_time_ago "$seconds_ago")

          # Extract subdomain for workspace services (Slack, Notion, etc.)
          local account_label="$service account"
          if [[ "$domain" =~ ^([^.]+)\.(slack|notion)\.com$ ]]; then
            local workspace="${BASH_REMATCH[1]}"
            account_label="$service account ($workspace.${BASH_REMATCH[2]}.com)"
          fi

          echo "  [$option_num] $account_label ($time_str, $visit_count visits)"
          option_to_profile+=("${profile_names[$i]}")
          option_to_account+=("$domain")
          option_num=$((option_num + 1))
        done <<< "$accounts_str"

        echo ""
      done

      # Prompt user to select account
      echo -n "Select account [1-$((option_num - 1))] or Ctrl+C to cancel: "
      read selection

      if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -ge $option_num ]; then
        echo "Invalid selection" >&2
        return 1
      fi

      local selected_profile="${option_to_profile[$((selection - 1))]}"
      local selected_domain="${option_to_account[$((selection - 1))]}"
      local source_path="$HOME/Library/Application Support/Google/Chrome/$selected_profile"

      echo ""
      echo "Selected: <$service> from Chrome.app profile '$selected_profile'"
      echo "Domain: $selected_domain"
      echo ""

      # Prompt for account identifier
      echo -n "Account identifier (email/username): "
      read account

      if [ -z "$account" ]; then
        echo "Error: Account identifier cannot be empty" >&2
        return 1
      fi

      local normalized_account=$(echo "$account" | tr '[:upper:]' '[:lower:]' | tr -s ' @.:-' '_' | sed 's/[^a-z0-9_]//g')
      local profile_name="${service}-${normalized_account}"
      local dest_path="$PROFILES_DIR/$profile_name"

      if [ -d "$dest_path" ]; then
        echo "Error: Profile '$profile_name' already exists" >&2
        return 1
      fi

      echo ""
      echo "Copying Chrome.app profile..."

      # Copy entire Chrome.app profile
      mkdir -p "$PROFILES_DIR"
      cp -r "$source_path" "$dest_path"

      # Write metadata
      write_profile_metadata "$dest_path" "$service" "$account" "Chrome.app/$selected_profile" "chrome_app" "$source_path"

      echo "✓ Profile imported: <$service> $account (Chrome.app/$selected_profile)"
      echo "  Filename: $profile_name"
      echo ""

      # Warn about multi-account services
      if [[ "$service" == "gmail" ]] || [[ "$service" == "google"* ]]; then
        echo "NOTE: Chrome.app profile may contain multiple Google accounts."
        echo "      All accounts were copied. Primary account: $account"
        echo ""
      fi

      echo "Use with:"
      echo "  $TOOL_NAME --profile $profile_name open URL"
      ;;

    enable)
      local name="$1"
      if [ -z "$name" ]; then
        echo "Usage: profile enable NAME" >&2
        return 1
      fi

      local profile_path="$PROFILES_DIR/$name"

      # Try fuzzy match if exact match doesn't exist
      if [ ! -d "$profile_path" ]; then
        local matched_name=$(prompt_fuzzy_match "$name")
        if [ $? -ne 0 ] || [ -z "$matched_name" ]; then
          echo "Error: Profile '$name' not found" >&2
          return 1
        fi
        name="$matched_name"
        profile_path="$PROFILES_DIR/$name"
      fi

      local status=$(read_profile_metadata "$profile_path" "status")
      if [ "$status" = "enabled" ]; then
        echo "Profile '$name' is already enabled"
        return 0
      fi

      update_profile_metadata "$profile_path" "status" "enabled"
      echo "✓ Profile '$name' enabled"
      ;;

    disable)
      local name="$1"
      if [ -z "$name" ]; then
        echo "Usage: profile disable NAME" >&2
        return 1
      fi

      local profile_path="$PROFILES_DIR/$name"

      # Try fuzzy match if exact match doesn't exist
      if [ ! -d "$profile_path" ]; then
        local matched_name=$(prompt_fuzzy_match "$name")
        if [ $? -ne 0 ] || [ -z "$matched_name" ]; then
          echo "Error: Profile '$name' not found" >&2
          return 1
        fi
        name="$matched_name"
        profile_path="$PROFILES_DIR/$name"
      fi

      local status=$(read_profile_metadata "$profile_path" "status")
      if [ "$status" = "disabled" ]; then
        echo "Profile '$name' is already disabled"
        return 0
      fi

      update_profile_metadata "$profile_path" "status" "disabled"
      echo "✓ Profile '$name' disabled"
      ;;

    rename)
      local old_name="$1"
      local new_name="$2"

      if [ -z "$old_name" ] || [ -z "$new_name" ]; then
        echo "Usage: profile rename OLD_NAME NEW_NAME" >&2
        return 1
      fi

      local old_normalized=$(normalize_profile_name "$old_name")
      local new_normalized=$(normalize_profile_name "$new_name")
      local old_path="$PROFILES_DIR/$old_normalized"
      local new_path="$PROFILES_DIR/$new_normalized"

      if [ ! -d "$old_path" ]; then
        echo "Error: Profile '$old_normalized' does not exist" >&2
        return 1
      fi

      if [ -d "$new_path" ]; then
        echo "Error: Profile '$new_normalized' already exists" >&2
        return 1
      fi

      mv "$old_path" "$new_path"

      # Update metadata display if it exists
      if [ -f "$new_path/.profile-meta.json" ]; then
        local old_display=$(read_profile_metadata "$new_path" "display")
        if [ -n "$old_display" ]; then
          # Keep service and source, just update account part
          local service=$(read_profile_metadata "$new_path" "service")
          local source=$(read_profile_metadata "$new_path" "source")
          local new_account=$(echo "$new_name" | sed "s/^${service}-//")
          update_profile_metadata "$new_path" "account" "$new_account"
          update_profile_metadata "$new_path" "display" "<$service> $new_account ($source)"
        fi
      fi

      echo "✓ Profile renamed: $old_normalized -> $new_normalized"
      ;;

    *)
      echo "Unknown profile subcommand: $subcommand" >&2
      echo "" >&2
      echo "Usage: profile <command> [args...]" >&2
      echo "" >&2
      echo "Commands:" >&2
      echo "  list                List all profiles (default)" >&2
      echo "  create URL          Create new profile by logging in" >&2
      echo "  import URL          Import credentials from Chrome.app" >&2
      echo "  enable NAME         Enable a profile" >&2
      echo "  disable NAME        Disable a profile" >&2
      echo "  rename OLD NEW      Rename a profile" >&2
      return 1
      ;;
  esac
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

COMMANDS (use in order of preference):

  1. URL Construction (PREFERRED - 10x faster):
    open URL          Navigate with URL params (construct URLs for search/filter)
    snapshot          View page state (smart diff shows changes)
      --full          Show full snapshot instead of diff
    inspect           Discover available URL parameters from page

  2. Selector-Based Interaction (when URL construction not possible):
    click SELECTOR    Click element by CSS selector or text
      --index N       Select Nth match when multiple elements found
    input SELECTOR VALUE  Set input value (React-compatible)
      --index N       Select Nth match when multiple elements found
    sendkey KEY       Send keyboard input (esc, enter, tab, arrows, etc.)

  3. Management:
    profile [NAME]    Manage credential profiles for auth
    tabs              List/activate/close tabs
    execute JS        Execute JavaScript code
    wait [SEL]        Wait for DOM stability or element

VISUAL COMMANDS (Edge case - when selectors unavailable):
  Use vision-based coordinates ONLY when CSS selectors don't work or aren't reliable.
  Workflow: screenshot → identify coordinates → click/hover/drag

  screenshot [OPTIONS]
                    Capture page for AI vision analysis (~1,280 tokens)
    --width=N       Viewport width (default: 1200)
    --height=N      Viewport height (default: 800)
    --quality=N     JPEG quality 1-100 (default: 70)
    --full          Capture full page

  click X Y         Click at pixel coordinates (from screenshot)
  hover X Y         Hover at pixel coordinates (from screenshot)
  drag X1 Y1 X2 Y2  Drag from coordinates to coordinates (from screenshot)

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

EXAMPLES (in order of preference):

  # 1. PREFERRED: URL construction (10x faster than clicking)
  $TOOL_NAME open "https://airbnb.com/s/Paris/homes?adults=2&checkin=2025-01-15"
  $TOOL_NAME snapshot              # See results instantly
  $TOOL_NAME inspect               # Discover what URL params are available

  # 2. Selector-based interaction (when URL construction not possible)
  $TOOL_NAME open "https://example.com"
  $TOOL_NAME click "Submit"        # Click by text
  $TOOL_NAME input "#email" "user@example.com"  # Fill form
  $TOOL_NAME sendkey esc           # Close modal

  # 3. EDGE CASE: Vision-based (only when selectors don't work)
  $TOOL_NAME screenshot            # AI analyzes page
  $TOOL_NAME click 600 130         # Click at coordinates (last resort)

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
    click)      cmd_click "$@" ;;
    input)      cmd_input "$@" ;;
    hover)      cmd_hover "$@" ;;
    drag)       cmd_drag "$@" ;;
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
  snapshot|inspect|open|wait|click|input|hover|drag|interact|sendkey|tabs|execute|esc|screenshot|pointer|profile)
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
