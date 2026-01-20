#!/usr/bin/env bash
# world/run.sh
# World - single source of truth for agent coordination

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMANDS_DIR="$SCRIPT_DIR/commands"

show_help() {
    cat <<'EOF'
world - Single source of truth for agent coordination

USAGE:
    world create <options>     Create event, task, or agent
    world check [options]      Query the log
    world spawn <task-id>      Start a task agent
    world watch [interval]     Start the daemon

CREATE:
    world create --event <type> <content>
    world create --task <id> <title> [--wait <cond>] [--need <criteria>]
    world create --agent task <title> [--wait <cond>] [--need <criteria>]
    world create --agent supervisor

CHECK:
    world check                    All entries
    world check --task             Only tasks
    world check --event            Only events
    world check --task --status pending

SPAWN:
    world spawn <task-id>          Start task in worktree

WATCH:
    world watch                    Daemon (5s interval)
    world watch 10                 Daemon (10s interval)

    The watch daemon:
    - Syncs MD changes to log
    - Spawns pending tasks
    - Recovers crashed tasks
    - Archives verified/canceled

EXAMPLES:
    world create --agent task "Fix login bug" --need "tests pass"
    world spawn fix-bug
    world check --task --status running
    world watch
EOF
}

# Route to command
case "${1:-}" in
    create)
        shift
        "$COMMANDS_DIR/create.sh" "$@"
        ;;
    check)
        shift
        "$COMMANDS_DIR/check.sh" "$@"
        ;;
    spawn)
        shift
        "$COMMANDS_DIR/spawn.sh" "$@"
        ;;
    watch)
        shift
        "$COMMANDS_DIR/watch.sh" "$@"
        ;;
    help|-h|--help|"")
        show_help
        ;;
    *)
        echo "Unknown command: $1" >&2
        echo "Run 'world help' for usage" >&2
        exit 1
        ;;
esac
