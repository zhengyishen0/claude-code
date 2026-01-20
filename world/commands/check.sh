#!/usr/bin/env bash
# world/commands/check.sh
# Query world log entries

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../paths.sh"

show_help() {
    cat <<'HELP'
check - Query world log entries

USAGE:
    check [options]

OPTIONS:
    --task              Filter task entries only
    --event             Filter event entries only
    --status <status>   Filter by status (pending, running, done, verified, canceled)
    --session <id>      Filter by session ID
    --tail <n>          Show last n entries (default: 20)
    --all               Show all entries

EXAMPLES:
    world check                           # Last 20 entries
    world check --task --status pending   # Pending tasks
    world check --session abc123          # Filter by session
    world check --all                     # All entries
HELP
}

# Defaults
FILTER_TYPE=""
FILTER_STATUS=""
FILTER_SESSION=""
TAIL_COUNT=20
SHOW_ALL=false

# Parse arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --task) FILTER_TYPE="task"; shift ;;
        --event) FILTER_TYPE="event"; shift ;;
        --status) FILTER_STATUS="$2"; shift 2 ;;
        --session) FILTER_SESSION="$2"; shift 2 ;;
        --tail) TAIL_COUNT="$2"; shift 2 ;;
        --all) SHOW_ALL=true; shift ;;
        help|-h|--help) show_help; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# Build grep pattern
PATTERN="."
if [ -n "$FILTER_TYPE" ]; then
    if [ "$FILTER_TYPE" = "task" ]; then
        PATTERN="\\[task:"
    else
        PATTERN="\\[event\\]"
    fi
fi

# Apply filters
RESULT=$(grep -E "$PATTERN" "$WORLD_LOG" 2>/dev/null || echo "")

if [ -n "$FILTER_STATUS" ]; then
    RESULT=$(echo "$RESULT" | grep -E "\\[task: $FILTER_STATUS\\]" || echo "")
fi

if [ -n "$FILTER_SESSION" ]; then
    RESULT=$(echo "$RESULT" | grep -E "$FILTER_SESSION" || echo "")
fi

# Output
if [ -z "$RESULT" ]; then
    echo "No entries found"
    exit 0
fi

if [ "$SHOW_ALL" = true ]; then
    echo "$RESULT"
else
    echo "$RESULT" | tail -n "$TAIL_COUNT"
fi
