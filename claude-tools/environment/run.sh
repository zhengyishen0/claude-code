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
    # Ensure log exists
    if [ ! -f "$ENV_LOG" ]; then
        touch "$ENV_LOG"
        echo "$MARKER_LINE" >> "$ENV_LOG"
        return 0
    fi

    # Find marker line number
    marker_line_num=$(grep -n "^$MARKER_LINE$" "$ENV_LOG" | cut -d: -f1 || echo "0")

    if [ "$marker_line_num" = "0" ]; then
        # No marker found, add it at the end
        echo "$MARKER_LINE" >> "$ENV_LOG"
        return 0
    fi

    # Read everything AFTER marker (unread events)
    total_lines=$(wc -l < "$ENV_LOG" | tr -d ' ')
    lines_after_marker=$((total_lines - marker_line_num))

    if [ "$lines_after_marker" -le 0 ]; then
        # Nothing after marker
        return 0
    fi

    # Get unread entries (everything after marker)
    new_entries=$(tail -n "$lines_after_marker" "$ENV_LOG")

    # Move marker to end (delete old marker, add at end)
    sed -i '' "/^$MARKER_LINE$/d" "$ENV_LOG"
    echo "$MARKER_LINE" >> "$ENV_LOG"

    # Output new entries
    echo "$new_entries"
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
    environment check              Read new events since marker
    environment event <args>       Add event to log

EXAMPLES:
    # Check for new events
    environment check

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

The READ-MARKER line separates read from unread events.
EOF
}

#──────────────────────────────────────────────────────────────
# Router
#──────────────────────────────────────────────────────────────

case "${1:-help}" in
    check)
        cmd_check
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
