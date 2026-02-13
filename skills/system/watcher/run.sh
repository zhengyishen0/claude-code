#!/bin/bash
#
# Watcher runner - auto-discovers and manages yaml-based watchers
#
# Usage:
#   run.sh start          # Start all watchers
#   run.sh stop           # Stop all watchers
#   run.sh status         # Show status of all watchers
#   run.sh start <name>   # Start specific watcher
#   run.sh stop <name>    # Stop specific watcher
#   run.sh list           # List discovered watchers
#

set -euo pipefail

# Paths
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")"
STATE_DIR="$HOME/.local/state/watchers"
PID_DIR="$STATE_DIR/pids"
LOG_DIR="$STATE_DIR/logs"

# Ensure directories exist
mkdir -p "$PID_DIR" "$LOG_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() { echo -e "${BLUE}[watchers]${NC} $*"; }
log_ok() { echo -e "${GREEN}[watchers]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[watchers]${NC} $*"; }
log_err() { echo -e "${RED}[watchers]${NC} $*" >&2; }

# Discover all watcher yaml files
discover_watchers() {
    find "$PROJECT_ROOT/skills" -path "*/watch/*.yaml" -type f 2>/dev/null | sort
}

# Parse yaml value (simple parser for flat yaml)
yaml_get() {
    local file="$1"
    local key="$2"
    grep "^${key}:" "$file" 2>/dev/null | sed "s/^${key}:[[:space:]]*//" | sed 's/[[:space:]]*$//'
}

# Parse yaml array
yaml_get_array() {
    local file="$1"
    local key="$2"
    local in_array=false
    local result=()

    while IFS= read -r line; do
        if [[ "$line" =~ ^${key}: ]]; then
            # Check for inline array [a, b, c]
            if [[ "$line" =~ \[.*\] ]]; then
                echo "$line" | sed "s/^${key}:[[:space:]]*\[//" | sed 's/\][[:space:]]*$//' | tr ',' '\n' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//'
                return
            fi
            in_array=true
            continue
        fi
        if $in_array; then
            if [[ "$line" =~ ^[[:space:]]*-[[:space:]] ]]; then
                echo "$line" | sed 's/^[[:space:]]*-[[:space:]]*//'
            elif [[ "$line" =~ ^[a-zA-Z] ]]; then
                break
            fi
        fi
    done < "$file"
}

# Get watcher name from yaml file
get_watcher_name() {
    local yaml_file="$1"
    yaml_get "$yaml_file" "name"
}

# Get PID file path for a watcher
get_pid_file() {
    local name="$1"
    echo "$PID_DIR/${name}.pid"
}

# Get log file path for a watcher
get_log_file() {
    local name="$1"
    echo "$LOG_DIR/${name}.log"
}

# Check if watcher is running
is_running() {
    local name="$1"
    local pid_file
    pid_file=$(get_pid_file "$name")

    if [[ -f "$pid_file" ]]; then
        local pid
        pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
        # Stale PID file
        rm -f "$pid_file"
    fi
    return 1
}

# Start fswatch watcher
start_fswatch() {
    local yaml_file="$1"
    local name="$2"
    local pid_file
    local log_file

    pid_file=$(get_pid_file "$name")
    log_file=$(get_log_file "$name")

    # Parse config
    local watch_path
    watch_path=$(yaml_get "$yaml_file" "path")
    local debounce
    debounce=$(yaml_get "$yaml_file" "debounce")
    debounce=${debounce:-15}

    # Build fswatch command
    local fswatch_args=(-0)

    # Events
    while IFS= read -r event; do
        [[ -n "$event" ]] && fswatch_args+=(--event "$event")
    done < <(yaml_get_array "$yaml_file" "events")

    # Excludes
    while IFS= read -r pattern; do
        [[ -n "$pattern" ]] && fswatch_args+=(--exclude "$pattern")
    done < <(yaml_get_array "$yaml_file" "exclude")

    # Resolve watch path (follow symlinks to get real path)
    local full_path
    if [[ "$watch_path" == /* ]]; then
        full_path="$watch_path"
    else
        full_path="$PROJECT_ROOT/$watch_path"
    fi
    # Resolve symlinks to real path (fswatch returns real paths)
    full_path="$(cd "$full_path" && pwd -P)"

    if [[ ! -d "$full_path" ]]; then
        log_err "Watch path does not exist: $full_path"
        return 1
    fi

    # Start the watcher process
    (
        # Create a subshell for the watcher
        exec > >(tee -a "$log_file") 2>&1

        echo ""
        echo "=== $name started at $(date) ==="
        echo "Watching: $full_path"
        echo "Debounce: ${debounce}s"
        echo ""

        # Debounce tracking (uses temp files instead of associative arrays for bash 3 compat)
        PENDING_DIR=$(mktemp -d)

        cleanup() {
            rm -rf "$PENDING_DIR"
            echo "=== $name stopped at $(date) ==="
            exit 0
        }
        trap cleanup EXIT INT TERM

        # Background checker for debounced files
        (
            while true; do
                sleep 2
                NOW=$(date +%s)

                for pending_file in "$PENDING_DIR"/*; do
                    [[ -f "$pending_file" ]] || continue

                    ORIGINAL_PATH=$(head -1 "$pending_file")
                    RULE_ACTION=$(tail -1 "$pending_file")
                    LAST_SEEN=$(stat -f %m "$pending_file" 2>/dev/null || stat -c %Y "$pending_file" 2>/dev/null)
                    ELAPSED=$((NOW - LAST_SEEN))

                    if [[ $ELAPSED -ge $debounce ]]; then
                        rm -f "$pending_file"
                        [[ -f "$ORIGINAL_PATH" ]] || continue

                        echo ""
                        echo "$(date '+%H:%M:%S') [EXEC] Processing: $ORIGINAL_PATH"
                        echo "$(date '+%H:%M:%S') [EXEC] Action: $RULE_ACTION"

                        # Run the action
                        local action_path
                        if [[ "$RULE_ACTION" == /* ]]; then
                            action_path="$RULE_ACTION"
                        else
                            action_path="$PROJECT_ROOT/$RULE_ACTION"
                        fi

                        if [[ -x "$action_path" ]]; then
                            "$action_path" "$ORIGINAL_PATH" || true
                        else
                            echo "$(date '+%H:%M:%S') [ERR] Action not executable: $action_path"
                        fi
                    fi
                done
            done
        ) &
        CHECKER_PID=$!

        # Parse rules from yaml
        parse_rules() {
            local in_rules=false
            local current_match=""
            local current_exclude=""
            local current_condition=""
            local current_action=""
            local rule_num=0

            while IFS= read -r line; do
                if [[ "$line" =~ ^rules: ]]; then
                    in_rules=true
                    continue
                fi

                if $in_rules; then
                    # New rule starts with "  - match:"
                    if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*match: ]]; then
                        # Save previous rule if exists
                        if [[ -n "$current_match" ]]; then
                            echo "RULE:$rule_num:$current_match:$current_exclude:$current_condition:$current_action"
                            ((rule_num++))
                        fi
                        current_match=$(echo "$line" | sed 's/.*match:[[:space:]]*//' | sed 's/"//g' | sed "s/'//g")
                        current_exclude=""
                        current_condition=""
                        current_action=""
                    elif [[ "$line" =~ ^[[:space:]]+exclude: ]]; then
                        current_exclude=$(echo "$line" | sed 's/.*exclude:[[:space:]]*//' | sed 's/"//g' | sed "s/'//g")
                    elif [[ "$line" =~ ^[[:space:]]+condition: ]]; then
                        current_condition=$(echo "$line" | sed 's/.*condition:[[:space:]]*//' | sed 's/"//g' | sed "s/'//g")
                    elif [[ "$line" =~ ^[[:space:]]+action: ]]; then
                        current_action=$(echo "$line" | sed 's/.*action:[[:space:]]*//' | sed 's/"//g' | sed "s/'//g")
                    elif [[ "$line" =~ ^[a-zA-Z] ]]; then
                        # End of rules section
                        break
                    fi
                fi
            done < "$yaml_file"

            # Save last rule
            if [[ -n "$current_match" ]]; then
                echo "RULE:$rule_num:$current_match:$current_exclude:$current_condition:$current_action"
            fi
        }

        # Load rules into arrays (bash 3 compatible)
        rule_matches=()
        rule_excludes=()
        rule_conditions=()
        rule_actions=()

        while IFS=: read -r _ num match exclude condition action; do
            rule_matches+=("$match")
            rule_excludes+=("$exclude")
            rule_conditions+=("$condition")
            rule_actions+=("$action")
        done < <(parse_rules)

        echo "Loaded ${#rule_matches[@]} rules"
        echo ""

        # Watch for changes
        fswatch "${fswatch_args[@]}" "$full_path" | while read -d "" event; do
            [[ "$event" == *.md ]] || continue
            [[ -f "$event" ]] || continue

            REL_PATH="${event#$full_path/}"

            # Check rules
            for i in "${!rule_matches[@]}"; do
                match="${rule_matches[$i]}"
                exclude="${rule_excludes[$i]}"
                condition="${rule_conditions[$i]}"
                action="${rule_actions[$i]}"

                # Check match
                if ! echo "$REL_PATH" | grep -qE "$match"; then
                    continue
                fi

                # Check exclude
                if [[ -n "$exclude" ]] && echo "$REL_PATH" | grep -qE "$exclude"; then
                    continue
                fi

                # Check condition
                if [[ -n "$condition" ]]; then
                    if ! eval "$condition \"$event\"" 2>/dev/null; then
                        continue
                    fi
                fi

                # Queue for debounce
                HASH=$(echo "$event:$action" | md5 2>/dev/null || echo "$event:$action" | md5sum | cut -d' ' -f1)
                HASH="${HASH:0:16}"
                PENDING_FILE="$PENDING_DIR/$HASH"

                if [[ ! -f "$PENDING_FILE" ]]; then
                    echo "$(date '+%H:%M:%S') [DETECT] $REL_PATH (waiting ${debounce}s...)"
                else
                    echo "$(date '+%H:%M:%S') [UPDATE] $REL_PATH (resetting timer...)"
                fi

                echo "$event" > "$PENDING_FILE"
                echo "$action" >> "$PENDING_FILE"

                break  # Only first matching rule
            done
        done

        kill $CHECKER_PID 2>/dev/null || true
    ) &

    local watcher_pid=$!
    echo $watcher_pid > "$pid_file"

    log_ok "Started $name (PID: $watcher_pid)"
}

# Start cron watcher
start_cron() {
    local yaml_file="$1"
    local name="$2"

    local schedule
    schedule=$(yaml_get "$yaml_file" "schedule")
    local action
    action=$(yaml_get "$yaml_file" "action")

    if [[ -z "$schedule" ]] || [[ -z "$action" ]]; then
        log_err "Cron watcher $name missing schedule or action"
        return 1
    fi

    # Resolve action path
    local action_path
    if [[ "$action" == /* ]]; then
        action_path="$action"
    else
        action_path="$PROJECT_ROOT/$action"
    fi

    # Create cron entry with marker
    local cron_marker="# watchers:$name"
    local cron_line="$schedule $action_path $cron_marker"

    # Check if already exists
    if crontab -l 2>/dev/null | grep -q "$cron_marker"; then
        log_warn "Cron entry for $name already exists"
        return 0
    fi

    # Add to crontab
    (crontab -l 2>/dev/null || true; echo "$cron_line") | crontab -

    log_ok "Added cron entry for $name: $schedule"
}

# Stop fswatch watcher
stop_fswatch() {
    local name="$1"
    local pid_file
    pid_file=$(get_pid_file "$name")

    if [[ -f "$pid_file" ]]; then
        local pid
        pid=$(cat "$pid_file")

        # Kill the process tree
        pkill -P "$pid" 2>/dev/null || true
        kill "$pid" 2>/dev/null || true

        rm -f "$pid_file"
        log_ok "Stopped $name"
    else
        log_warn "$name is not running"
    fi
}

# Stop cron watcher
stop_cron() {
    local name="$1"
    local cron_marker="# watchers:$name"

    if crontab -l 2>/dev/null | grep -q "$cron_marker"; then
        crontab -l 2>/dev/null | grep -v "$cron_marker" | crontab -
        log_ok "Removed cron entry for $name"
    else
        log_warn "No cron entry found for $name"
    fi
}

# Start a watcher by yaml file
start_watcher() {
    local yaml_file="$1"

    local name
    name=$(get_watcher_name "$yaml_file")
    local type
    type=$(yaml_get "$yaml_file" "type")

    if [[ -z "$name" ]] || [[ -z "$type" ]]; then
        log_err "Invalid yaml: $yaml_file (missing name or type)"
        return 1
    fi

    case "$type" in
        fswatch)
            if is_running "$name"; then
                log_warn "$name is already running"
                return 0
            fi
            start_fswatch "$yaml_file" "$name"
            ;;
        cron)
            start_cron "$yaml_file" "$name"
            ;;
        *)
            log_err "Unknown watcher type: $type"
            return 1
            ;;
    esac
}

# Stop a watcher by name
stop_watcher() {
    local yaml_file="$1"

    local name
    name=$(get_watcher_name "$yaml_file")
    local type
    type=$(yaml_get "$yaml_file" "type")

    case "$type" in
        fswatch)
            stop_fswatch "$name"
            ;;
        cron)
            stop_cron "$name"
            ;;
    esac
}

# Show status of a watcher
show_status() {
    local yaml_file="$1"

    local name
    name=$(get_watcher_name "$yaml_file")
    local type
    type=$(yaml_get "$yaml_file" "type")

    case "$type" in
        fswatch)
            if is_running "$name"; then
                local pid
                pid=$(cat "$(get_pid_file "$name")")
                echo -e "  ${GREEN}[running]${NC} $name (fswatch, PID: $pid)"
            else
                echo -e "  ${RED}[stopped]${NC} $name (fswatch)"
            fi
            ;;
        cron)
            local cron_marker="# watchers:$name"
            if crontab -l 2>/dev/null | grep -q "$cron_marker"; then
                local schedule
                schedule=$(crontab -l 2>/dev/null | grep "$cron_marker" | awk '{print $1, $2, $3, $4, $5}')
                echo -e "  ${GREEN}[active]${NC} $name (cron: $schedule)"
            else
                echo -e "  ${RED}[inactive]${NC} $name (cron)"
            fi
            ;;
    esac
}

# Find yaml file by watcher name
find_yaml_by_name() {
    local search_name="$1"

    while IFS= read -r yaml_file; do
        local name
        name=$(get_watcher_name "$yaml_file")
        if [[ "$name" == "$search_name" ]]; then
            echo "$yaml_file"
            return 0
        fi
    done < <(discover_watchers)

    return 1
}

# Commands
cmd_list() {
    log "Discovered watchers:"
    while IFS= read -r yaml_file; do
        local name
        name=$(get_watcher_name "$yaml_file")
        local type
        type=$(yaml_get "$yaml_file" "type")
        local rel_path="${yaml_file#$PROJECT_ROOT/}"
        echo "  $name ($type) - $rel_path"
    done < <(discover_watchers)
}

cmd_status() {
    log "Watcher status:"
    local found=false
    while IFS= read -r yaml_file; do
        found=true
        show_status "$yaml_file"
    done < <(discover_watchers)

    if ! $found; then
        echo "  No watchers found"
    fi
}

cmd_start() {
    local name="${1:-}"

    if [[ -n "$name" ]]; then
        local yaml_file
        if yaml_file=$(find_yaml_by_name "$name"); then
            start_watcher "$yaml_file"
        else
            log_err "Watcher not found: $name"
            return 1
        fi
    else
        log "Starting all watchers..."
        while IFS= read -r yaml_file; do
            start_watcher "$yaml_file"
        done < <(discover_watchers)
    fi
}

cmd_stop() {
    local name="${1:-}"

    if [[ -n "$name" ]]; then
        local yaml_file
        if yaml_file=$(find_yaml_by_name "$name"); then
            stop_watcher "$yaml_file"
        else
            log_err "Watcher not found: $name"
            return 1
        fi
    else
        log "Stopping all watchers..."
        while IFS= read -r yaml_file; do
            stop_watcher "$yaml_file"
        done < <(discover_watchers)
    fi
}

cmd_logs() {
    local name="${1:-}"

    if [[ -n "$name" ]]; then
        local log_file
        log_file=$(get_log_file "$name")
        if [[ -f "$log_file" ]]; then
            tail -f "$log_file"
        else
            log_err "No log file for $name"
            return 1
        fi
    else
        log_err "Usage: run.sh logs <name>"
        return 1
    fi
}

# Main
case "${1:-}" in
    list)
        cmd_list
        ;;
    status)
        cmd_status
        ;;
    start)
        cmd_start "${2:-}"
        ;;
    stop)
        cmd_stop "${2:-}"
        ;;
    logs)
        cmd_logs "${2:-}"
        ;;
    *)
        echo "Watcher runner - auto-discovers yaml-based watchers"
        echo ""
        echo "Usage:"
        echo "  $0 list              List discovered watchers"
        echo "  $0 status            Show status of all watchers"
        echo "  $0 start             Start all watchers"
        echo "  $0 start <name>      Start specific watcher"
        echo "  $0 stop              Stop all watchers"
        echo "  $0 stop <name>       Stop specific watcher"
        echo "  $0 logs <name>       Tail logs for a watcher"
        echo ""
        echo "Watchers are discovered from: skills/*/*/watch/*.yaml"
        echo "State directory: $STATE_DIR"
        ;;
esac
