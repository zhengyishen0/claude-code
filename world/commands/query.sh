#!/usr/bin/env bash
# world/commands/query.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../paths.sh"

show_help() {
    cat <<'HELP'
query - Search world log with patterns

USAGE:
    query <pattern>

EXAMPLES:
    world query "git:commit"
    world query "task.*pending"
HELP
}

[ $# -lt 1 ] && { show_help; exit 0; }
[ "$1" = "help" ] || [ "$1" = "-h" ] && { show_help; exit 0; }

grep -E "$1" "$WORLD_LOG" 2>/dev/null || echo "No matches found"
