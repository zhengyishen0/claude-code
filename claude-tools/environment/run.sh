#!/usr/bin/env bash
# claude-tools/environment/run.sh
# Environment event log tool

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_LOG="$SCRIPT_DIR/environment.log"
MARKER_LINE="=================READ-MARKER================="

#──────────────────────────────────────────────────────────────
# Commands
#──────────────────────────────────────────────────────────────

cmd_check() {
    local agent_id="${1:-}"

    # Ensure log exists
    if [ ! -f "$ENV_LOG" ]; then
        touch "$ENV_LOG"
        echo "$MARKER_LINE" >> "$ENV_LOG"
    fi

    # Find LAST marker line number
    marker_line_num=$(grep -n "^$MARKER_LINE$" "$ENV_LOG" | tail -1 | cut -d: -f1 || echo "0")

    if [ "$marker_line_num" = "0" ]; then
        # No marker found, add it at the end
        echo "$MARKER_LINE" >> "$ENV_LOG"
        marker_line_num=$(wc -l < "$ENV_LOG" | tr -d ' ')
    fi

    # Read everything AFTER last marker (unread events)
    total_lines=$(wc -l < "$ENV_LOG" | tr -d ' ')
    lines_after_marker=$((total_lines - marker_line_num))

    local event_count=0
    local new_entries=""

    if [ "$lines_after_marker" -gt 0 ]; then
        # Get unread entries (everything after last marker)
        new_entries=$(tail -n "$lines_after_marker" "$ENV_LOG")
        # Filter out sleep events from both output and count
        local filtered=$(echo "$new_entries" | grep -v '\[sleep:' || true)
        if [ -n "$filtered" ]; then
            event_count=$(echo "$filtered" | wc -l | tr -d ' ')
            new_entries="$filtered"  # Use filtered entries for output too
        else
            event_count=0
            new_entries=""
        fi
    fi

    # ALWAYS add read event (even if event_count is 0)
    timestamp=$(date -u -Iseconds)
    if [ -n "$agent_id" ]; then
        echo "[$timestamp] [agent $agent_id] checked all $event_count events above" >> "$ENV_LOG"
    else
        echo "[$timestamp] [agent] checked all $event_count events above" >> "$ENV_LOG"
    fi

    # ALWAYS add new marker at end
    echo "$MARKER_LINE" >> "$ENV_LOG"

    # Output
    if [ "$event_count" -eq 0 ]; then
        echo "no new events"
    else
        echo "$new_entries"
    fi
}

cmd_event() {
    if [ $# -lt 2 ]; then
        echo "Usage: environment event [source] [description]"
        echo "   or: environment event [source] [task-id:status] description"
        exit 1
    fi

    # Ensure log exists
    if [ ! -f "$ENV_LOG" ]; then
        touch "$ENV_LOG"
        echo "$MARKER_LINE" >> "$ENV_LOG"
    fi

    timestamp=$(date -u -Iseconds)
    source="$1"
    shift

    # Build entry
    entry="[$timestamp] $source $*"

    # Append after marker (or at end if no marker)
    echo "$entry" >> "$ENV_LOG"
}

cmd_help() {
    cat <<EOF
environment - Event log tool

USAGE:
    environment check [agent-id]   Read new events since marker
    environment event <args>       Add event to log

EXAMPLES:
    # Check for new events (no agent-id)
    environment check
    # Returns: events or "no new events"

    # Check with specific agent ID
    environment check manager-abc123

    # Add task event
    environment event [agent] [task-001:active] "build website"

    # Add note event
    environment event [user] "deadline is Jan 31"

    # Add system event
    environment event [system] [12345-a7f3c1:started] "manager started"

FORMAT:
    [timestamp] [source] [task-id:status] description
    [timestamp] [source] description

SOURCES:
    user, agent, system, fs, webhook, cron

BEHAVIOR:
    Every check call ALWAYS adds:
    1. Read event: "[timestamp] [agent xxx] checked all N events above"
    2. Read marker: "=================READ-MARKER================="

    This creates a complete audit trail even when no events are read (N=0).
EOF
}

#──────────────────────────────────────────────────────────────
# Router
#──────────────────────────────────────────────────────────────

case "${1:-help}" in
    check)
        shift
        cmd_check "$@"
        ;;
    event)
        shift
        cmd_event "$@"
        ;;
    help|-h|--help)
        cmd_help
        ;;
    *)
        echo "Unknown command: $1"
        echo "Run 'environment help' for usage"
        exit 1
        ;;
esac
