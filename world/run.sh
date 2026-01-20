#!/usr/bin/env bash
# world/run.sh - Single source of truth for agent coordination

set -euo pipefail

: "${PROJECT_DIR:?PROJECT_DIR not set - source env.sh}"

COMMANDS_DIR="$PROJECT_DIR/world/commands"
WORLD_LOG="$PROJECT_DIR/world/world.log"
TASKS_DIR="$PROJECT_DIR/world/tasks"

show_help() {
    cat <<'HELP'
world - Agent coordination

COMMANDS:
    world create <title>              Create task (auto-generates ID)
    world log event <type> <msg>      Log an event
    world log task <status> ...       Log task status
    world spawn <task-id>             Start agent in worktree
    world watch [interval]            Run polling daemon (foreground)
    world daemon <cmd>                Shortcut for: daemon world-watch <cmd>

LOG FORMAT:
    [timestamp] [event: <type>] <message>
    [timestamp] [task: <status>] <id>(<title>) | wait: <w> | need: <n>

SEE ALSO:
    daemon help                       Full daemon management
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
    daemon)
        shift
        "$PROJECT_DIR/daemon/run.sh" world-watch "$@"
        ;;
    help|-h|--help)
        show_help
        ;;
    *)
        show_entries
        ;;
esac
