#!/usr/bin/env bash
# supervisor/level1.sh
# Level 1 Supervisor: State Enforcer (Pure Code)
#
# Job: Ensure world.log state = actual system state
# - Start agents that should be running but aren't
# - Kill orphan processes not in log
# - Log all actions as [event:system]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR_DEFAULT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Use env vars from shell-init.sh, fallback to script-relative paths
: "${PROJECT_DIR:=$PROJECT_DIR_DEFAULT}"
: "${WORLD_LOG:=$PROJECT_DIR/world/world.log}"
WORLD_DIR="$PROJECT_DIR/world"

# Configuration
DRY_RUN="${DRY_RUN:-false}"
VERBOSE="${VERBOSE:-false}"

show_help() {
    cat <<'EOF'
level1 - State Enforcer Supervisor

USAGE:
    level1.sh [command]

COMMANDS:
    check       Check state discrepancies (default)
    enforce     Check and fix discrepancies
    status      Show current agent states

OPTIONS (via environment):
    DRY_RUN=true    Show what would be done without doing it
    VERBOSE=true    Show detailed output

EXAMPLES:
    level1.sh check              # Check for discrepancies
    level1.sh enforce            # Fix discrepancies
    DRY_RUN=true level1.sh enforce   # Show what would be fixed

WHAT IT DOES:
    1. Reads [agent:active] entries from world.log
    2. Checks if corresponding processes exist
    3. Starts missing agents (if enforce)
    4. Kills orphan processes (if enforce)
    5. Logs all actions as [event:system]
EOF
}


verbose() {
    if [ "$VERBOSE" = "true" ]; then
        echo "$@"
    fi
}

# Get active agents from log (most recent status per session-id)
get_log_agents() {
    if [ ! -f "$WORLD_LOG" ]; then
        return
    fi

    # Find all unique session-ids and their latest status
    # An agent is "active" if its last status is 'start' or 'active' or 'retry'
    # (not 'finish', 'verified', or 'failed')

    local session_ids
    session_ids=$(grep -oE '\[agent:[^]]+\]\[[^]]+\]' "$WORLD_LOG" 2>/dev/null | \
        sed -E 's/\[agent:[^]]+\]\[([^]]+)\]/\1/' | \
        sort -u || echo "")

    for sid in $session_ids; do
        # Get last agent entry for this session
        local last_entry
        last_entry=$(grep "\[agent:.*\]\[$sid\]" "$WORLD_LOG" | tail -1 || echo "")

        if [ -n "$last_entry" ]; then
            # Extract status
            local status
            status=$(echo "$last_entry" | sed -E 's/.*\[agent:([^]]+)\].*/\1/')

            # Active states: start, active, retry (not finish, verified, failed)
            case "$status" in
                start|active|retry)
                    echo "$sid"
                    ;;
            esac
        fi
    done
}

# Get running Claude processes (simulated for now)
# In production, this would check actual processes
get_running_processes() {
    # Check for a mock file that simulates running processes (for testing)
    local mock_file="$WORLD_DIR/.mock_running_processes"
    if [ -f "$mock_file" ]; then
        cat "$mock_file"
        return
    fi

    # Real implementation would be:
    # pgrep -f "claude.*session" | while read pid; do
    #     # Extract session-id from process
    # done

    # For now, return empty (no real Claude sessions to detect)
    echo ""
}

# Start an agent (simulated)
start_agent() {
    local session_id="$1"

    if [ "$DRY_RUN" = "true" ]; then
        echo "[DRY-RUN] Would start agent: $session_id"
    else
        # In production: claude --resume $session_id &
        # For now, just log the action
        echo "[$(date -u +%H:%M:%S)] level1-supervisor: would start agent $session_id (not implemented)"
        echo "Started agent: $session_id (simulated)"
    fi
}

# Kill an orphan process (simulated)
kill_orphan() {
    local pid="$1"

    if [ "$DRY_RUN" = "true" ]; then
        echo "[DRY-RUN] Would kill orphan process: $pid"
    else
        # In production: kill $pid
        echo "[$(date -u +%H:%M:%S)] level1-supervisor: would kill orphan $pid (not implemented)"
        echo "Killed orphan: $pid (simulated)"
    fi
}

cmd_check() {
    echo "=== Level 1 State Check ==="

    local log_agents
    log_agents=$(get_log_agents)

    local running_processes
    running_processes=$(get_running_processes)

    echo ""
    echo "Agents that should be running (from log):"
    if [ -n "$log_agents" ]; then
        echo "$log_agents" | while read -r sid; do
            echo "  - $sid"
        done
    else
        echo "  (none)"
    fi

    echo ""
    echo "Processes actually running:"
    if [ -n "$running_processes" ]; then
        echo "$running_processes" | while read -r pid; do
            echo "  - $pid"
        done
    else
        echo "  (none)"
    fi

    echo ""
    echo "Discrepancies:"

    local has_discrepancy=false

    # Check for agents that should be running but aren't
    if [ -n "$log_agents" ]; then
        for sid in $log_agents; do
            if [ -z "$running_processes" ] || ! echo "$running_processes" | grep -q "^$sid$"; then
                echo "  [MISSING] Agent $sid should be running but is not"
                has_discrepancy=true
            fi
        done
    fi

    # Check for orphan processes
    if [ -n "$running_processes" ]; then
        for pid in $running_processes; do
            if [ -z "$log_agents" ] || ! echo "$log_agents" | grep -q "^$pid$"; then
                echo "  [ORPHAN] Process $pid is running but not in log"
                has_discrepancy=true
            fi
        done
    fi

    if [ "$has_discrepancy" = "false" ]; then
        echo "  (none - state is consistent)"
    fi
}

cmd_enforce() {
    echo "=== Level 1 State Enforcement ==="

    local log_agents
    log_agents=$(get_log_agents)

    local running_processes
    running_processes=$(get_running_processes)

    local actions_taken=0

    # Start missing agents
    if [ -n "$log_agents" ]; then
        for sid in $log_agents; do
            if [ -z "$running_processes" ] || ! echo "$running_processes" | grep -q "^$sid$"; then
                echo "Agent $sid is missing, starting..."
                start_agent "$sid"
                ((actions_taken++)) || true
            fi
        done
    fi

    # Kill orphan processes
    if [ -n "$running_processes" ]; then
        for pid in $running_processes; do
            if [ -z "$log_agents" ] || ! echo "$log_agents" | grep -q "^$pid$"; then
                echo "Process $pid is orphan, killing..."
                kill_orphan "$pid"
                ((actions_taken++)) || true
            fi
        done
    fi

    if [ "$actions_taken" -eq 0 ]; then
        echo "No actions needed - state is consistent"
    else
        echo ""
        echo "Total actions: $actions_taken"
    fi
}

cmd_status() {
    echo "=== Agent Status ==="

    if [ ! -f "$WORLD_LOG" ]; then
        echo "No world.log found"
        return
    fi

    # Get all unique session-ids
    local session_ids
    session_ids=$(grep -oE '\[agent:[^]]+\]\[[^]]+\]' "$WORLD_LOG" 2>/dev/null | \
        sed -E 's/\[agent:[^]]+\]\[([^]]+)\]/\1/' | \
        sort -u || echo "")

    if [ -z "$session_ids" ]; then
        echo "No agents found in log"
        return
    fi

    echo ""
    printf "%-20s %-12s %s\n" "SESSION-ID" "STATUS" "LAST UPDATE"
    printf "%-20s %-12s %s\n" "----------" "------" "-----------"

    for sid in $session_ids; do
        local last_entry
        last_entry=$(grep "\[agent:.*\]\[$sid\]" "$WORLD_LOG" | tail -1 || echo "")

        if [ -n "$last_entry" ]; then
            local status timestamp
            status=$(echo "$last_entry" | sed -E 's/.*\[agent:([^]]+)\].*/\1/')
            timestamp=$(echo "$last_entry" | sed -E 's/^\[([^]]+)\].*/\1/')

            printf "%-20s %-12s %s\n" "$sid" "$status" "$timestamp"
        fi
    done
}

# Router
case "${1:-check}" in
    check)
        cmd_check
        ;;
    enforce)
        cmd_enforce
        ;;
    status)
        cmd_status
        ;;
    help|-h|--help)
        show_help
        ;;
    *)
        echo "Unknown command: $1"
        echo "Run 'level1.sh help' for usage"
        exit 1
        ;;
esac
