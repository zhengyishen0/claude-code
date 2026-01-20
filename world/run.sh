#!/usr/bin/env bash
# world/run.sh - Single source of truth for agent coordination

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMANDS_DIR="$SCRIPT_DIR/commands"
source "$SCRIPT_DIR/../paths.sh"

show_help() {
    cat <<'HELP'
world - Agent coordination

COMMANDS:
    world create <title>              Create task (auto-generates ID)
    world log event <type> <msg>      Log an event
    world log task <status> ...       Log task status
    world spawn <task-id>             Start agent in worktree
    world watch [interval]            Run daemon (sync/spawn/recover)

LOG FORMAT:
    [timestamp] [event: <type>] <message>
    [timestamp] [task: <status>] <id>(<title>) | wait: <w> | need: <n>
HELP
}

show_entries() {
    if [ -f "$WORLD_LOG" ]; then
        tail -20 "$WORLD_LOG"
        echo ""
    fi
    show_help
}

# Route
case "${1:-}" in
    create)
        shift
        "$COMMANDS_DIR/create.sh" "$@"
        ;;
    log)
        shift
        "$COMMANDS_DIR/log.sh" "$@"
        ;;
    spawn)
        shift
        "$COMMANDS_DIR/spawn.sh" "$@"
        ;;
    watch)
        shift
        "$COMMANDS_DIR/watch.sh" "$@"
        ;;
    help|-h|--help)
        show_help
        ;;
    *)
        show_entries
        ;;
esac
