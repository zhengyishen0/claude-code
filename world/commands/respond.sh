#!/usr/bin/env bash
# world/commands/respond.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../paths.sh"

show_help() {
    cat <<'HELP'
respond - Log a response to an event

USAGE:
    respond <event-type> <response>

EXAMPLES:
    world respond "user:request" "acknowledged"
HELP
}

[ $# -lt 2 ] && { show_help; exit 0; }
[ "$1" = "help" ] || [ "$1" = "-h" ] && { show_help; exit 0; }

timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
entry="[$timestamp] [event] response:$1 | $2"
echo "$entry" >> "$WORLD_LOG"
echo "$entry"
