#!/usr/bin/env bash
# world/commands/record.sh - Record events to world.log

set -euo pipefail

: "${PROJECT_DIR:?PROJECT_DIR not set - source env.sh}"

WORLD_LOG="$PROJECT_DIR/world/world.log"

show_help() {
    cat <<'HELP'
record - Record events to world.log

USAGE:
    world record <type> <message>
    world record task <status> <id> <title> [wait] [need]

EVENT TYPES:
    system      Daemon/system events
    git:commit  Git commits
    git:merge   Git merges
    error       Errors
    user        User notes

INTERNAL (used by daemon):
    task        Task status changes (synced from task MD files)

FORMAT:
    [timestamp] [event: <type>] <message>
    [timestamp] [task: <status>] <id>(<title>) | wait: <w> | need: <n>

EXAMPLES:
    world record "system" "daemon started"
    world record "git:commit" "fix: login bug"
HELP
}

record_event() {
    local type="$1"
    local message="$2"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "[$timestamp] [event: $type] $message" >> "$WORLD_LOG"
}

record_task() {
    local status="$1"
    local id="$2"
    local title="$3"
    local wait="${4:--}"
    local need="${5:--}"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "[$timestamp] [task: $status] $id($title) | wait: $wait | need: $need" >> "$WORLD_LOG"
}

# Ensure log directory exists
mkdir -p "$(dirname "$WORLD_LOG")"

if [ $# -lt 1 ] || [ "${1:-}" = "help" ] || [ "${1:-}" = "-h" ]; then
    show_help
    exit 0
fi

# Special case: internal task recording (used by daemon)
if [ "$1" = "task" ]; then
    [ $# -lt 4 ] && { echo "Usage: world record task <status> <id> <title> [wait] [need]" >&2; exit 1; }
    record_task "$2" "$3" "$4" "${5:--}" "${6:--}"
    exit 0
fi

# Normal event recording
[ $# -lt 2 ] && { echo "Usage: world record <type> <message>" >&2; exit 1; }
record_event "$1" "$2"
