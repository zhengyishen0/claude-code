#!/usr/bin/env bash
# world/commands/log.sh - Unified logging for events and tasks

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../paths.sh"

show_help() {
    cat <<'HELP'
log - Write entries to world.log

USAGE:
    world log event <type> <message>
    world log task <status> <id> <title> [wait] [need]

TYPES:
    event   Log an event (git:commit, system, error, etc.)
    task    Log a task status change

FORMAT:
    [timestamp] [event: <type>] <message>
    [timestamp] [task: <status>] <id>(<title>) | wait: <w> | need: <n>

EXAMPLES:
    world log event "system" "daemon started"
    world log event "git:commit" "fix: login bug"
    world log task "pending" "abc123" "Fix bug" "-" "-"
HELP
}

log_event() {
    local type="$1"
    local message="$2"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "[$timestamp] [event: $type] $message" >> "$WORLD_LOG"
}

log_task() {
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

case "$1" in
    event)
        [ $# -lt 3 ] && { echo "Usage: world log event <type> <message>" >&2; exit 1; }
        log_event "$2" "$3"
        ;;
    task)
        [ $# -lt 4 ] && { echo "Usage: world log task <status> <id> <title> [wait] [need]" >&2; exit 1; }
        log_task "$2" "$3" "$4" "${5:--}" "${6:--}"
        ;;
    *)
        echo "Error: Unknown log type '$1'. Use 'event' or 'task'." >&2
        exit 1
        ;;
esac
