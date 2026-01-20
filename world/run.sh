#!/usr/bin/env bash
# world/run.sh - Single source of truth for agent coordination

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMANDS_DIR="$SCRIPT_DIR/commands"

# Use env vars from shell-init.sh, fallback to defaults
: "${WORLD_LOG:=$SCRIPT_DIR/world.log}"
: "${TASKS_DIR:=$SCRIPT_DIR/tasks}"

show_help() {
    cat <<'HELP'
world - Agent coordination

COMMANDS:
    world create <title>              Create task (auto-generates ID)
    world log event <type> <msg>      Log an event
    world log task <status> ...       Log task status
    world spawn <task-id>             Start agent in worktree
    world watch [interval]            Run polling daemon
    world daemon <cmd>                Manage fswatch daemon (LaunchAgent)

DAEMON COMMANDS:
    world daemon install              Install and start LaunchAgent
    world daemon uninstall            Stop and remove LaunchAgent
    world daemon {start|stop|status}  Control the daemon
    world daemon log                  Tail daemon log

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
    daemon)
        shift
        "$COMMANDS_DIR/daemon-install.sh" "$@"
        ;;
    help|-h|--help)
        show_help
        ;;
    *)
        show_entries
        ;;
esac
