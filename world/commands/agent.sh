#!/usr/bin/env bash
# world/commands/agent.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../paths.sh"

show_help() {
    cat <<'HELP'
agent - Log agent lifecycle events

USAGE:
    agent start <session-id> <description>
    agent finish <session-id> <description>

EXAMPLES:
    world agent start abc123 "Starting task"
    world agent finish abc123 "Completed"
HELP
}

[ $# -lt 3 ] && { show_help; exit 0; }
[ "$1" = "help" ] || [ "$1" = "-h" ] && { show_help; exit 0; }

action="$1"
session="$2"
desc="$3"

timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
entry="[$timestamp] [event] agent:$action:$session | $desc"
echo "$entry" >> "$WORLD_LOG"
echo "$entry"
