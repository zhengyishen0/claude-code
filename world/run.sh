#!/usr/bin/env bash
# world/run.sh
# World - single source of truth for agent coordination

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMANDS_DIR="$SCRIPT_DIR/commands"
source "$SCRIPT_DIR/../paths.sh"

# Log an event to world.log
log_event() {
    local type="$1"
    local message="$2"
    local entry="[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [event] $type | $message"
    echo "$entry" >> "$WORLD_LOG"
    echo "$entry"
}

show_help() {
    cat <<'HELP'
world - Single source of truth for agent coordination

USAGE:
    world create <id> <title>  Create a task
    world log [type] [msg]     Log event (or show recent)
    world spawn <task-id>      Start a task agent
    world watch [interval]     Start the daemon

CREATE:
    world create fix-bug "Fix the login bug"
    world create task-1 "Title" --wait "condition" --need "criteria"

LOG:
    world log                      Show last 20 entries
    world log "system" "message"   Log an event

SPAWN:
    world spawn <task-id>          Start task in worktree

WATCH:
    world watch                    Daemon (5s interval)
    world watch 10                 Daemon (10s interval)

LOG FORMAT:
    [timestamp] [event] <type> | <message>
    [timestamp] [task: <status>] <id>(<title>) | file: ... | wait: ... | need: ...

QUERY EXAMPLES (use grep):
    grep "\[task:" world/world.log
    grep "\[task: pending\]" world/world.log
    grep "\[event\] git:" world/world.log
    tail -20 world/world.log
HELP
}

# Route to command
case "${1:-}" in
    create)
        shift
        "$COMMANDS_DIR/create.sh" "$@"
        ;;
    log)
        shift
        if [ $# -lt 2 ]; then
            # No args or 1 arg: show recent entries
            if [ -f "$WORLD_LOG" ]; then
                tail -20 "$WORLD_LOG"
            else
                echo "No log entries yet"
            fi
        else
            log_event "$1" "$2"
        fi
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
