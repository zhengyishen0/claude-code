#!/usr/bin/env bash
# world/commands/event.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../paths.sh"

show_help() {
    cat <<'HELP'
event - Log an event (shorthand for create --event)

USAGE:
    event <type> <message>

EXAMPLES:
    world event "git:commit" "fix: bug"
    world event "system" "started"
HELP
}

[ $# -lt 2 ] && { show_help; exit 0; }
[ "$1" = "help" ] || [ "$1" = "-h" ] && { show_help; exit 0; }

timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
entry="[$timestamp] [event] $1 | $2"
echo "$entry" >> "$WORLD_LOG"
echo "$entry"
