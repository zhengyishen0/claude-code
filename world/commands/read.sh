#!/usr/bin/env bash
# world/commands/read.sh
# Unified read command for events and tasks

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORLD_LOG="$SCRIPT_DIR/../world.log"

show_help() {
    cat <<'EOF'
read - Read entries from world.log

USAGE:
    read [options]

OPTIONS:
    --event              Only show events
    --task               Only show tasks
    --type <type>        Filter events by type (requires --event)
    --status <status>    Filter tasks by status (requires --task)
    --session <id>       Filter by session ID
    --since <date>       Filter entries since date (YYYY-MM-DD)
    --tail <n>           Show last n entries (default: all)

EXAMPLES:
    read                           # All entries
    read --event                   # Only events
    read --task                    # Only tasks
    read --event --type git:commit # Events of specific type
    read --task --status pending   # Pending tasks
    read --session abc123          # All entries for session
    read --since 2024-01-19        # Entries since date
    read --tail 20                 # Last 20 entries

FORMAT:
    Event:  [timestamp] [event] <type> | <content>
    Task:   [timestamp] [task] <id> | <status> | ...
EOF
}

# Check if log exists
if [ ! -f "$WORLD_LOG" ]; then
    echo "No entries yet."
    exit 0
fi

# Parse arguments
filter_event=false
filter_task=false
filter_type=""
filter_status=""
filter_session=""
filter_since=""
tail_count=""

while [ $# -gt 0 ]; do
    case "$1" in
        --event)
            filter_event=true
            shift
            ;;
        --task)
            filter_task=true
            shift
            ;;
        --type)
            shift
            filter_type="$1"
            shift
            ;;
        --status)
            shift
            filter_status="$1"
            shift
            ;;
        --session)
            shift
            filter_session="$1"
            shift
            ;;
        --since)
            shift
            filter_since="$1"
            shift
            ;;
        --tail)
            shift
            tail_count="$1"
            shift
            ;;
        help|-h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Error: Unknown option '$1'"
            echo "Run 'world read --help' for usage"
            exit 1
            ;;
    esac
done

# Build grep pattern
pattern=""

if $filter_event && ! $filter_task; then
    pattern="\[event\]"
elif $filter_task && ! $filter_event; then
    pattern="\[task\]"
fi

# Read and filter
result=$(cat "$WORLD_LOG")

# Filter by event/task type
if [ -n "$pattern" ]; then
    result=$(echo "$result" | grep "$pattern" || true)
fi

# Filter by event type
if [ -n "$filter_type" ]; then
    result=$(echo "$result" | grep "\[event\] $filter_type" || true)
fi

# Filter by task status
if [ -n "$filter_status" ]; then
    result=$(echo "$result" | grep "\[task\].*| $filter_status" || true)
fi

# Filter by session
if [ -n "$filter_session" ]; then
    result=$(echo "$result" | grep "$filter_session" || true)
fi

# Filter by date (simple grep-based approach)
if [ -n "$filter_since" ]; then
    # Filter entries starting from the date
    result=$(echo "$result" | grep -E "^\[$filter_since" || true)
fi

# Apply tail
if [ -n "$tail_count" ] && [ -n "$result" ]; then
    result=$(echo "$result" | tail -n "$tail_count")
fi

# Output
if [ -z "$result" ]; then
    echo "No matching entries."
else
    echo "$result"
fi
