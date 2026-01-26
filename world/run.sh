#!/usr/bin/env bash
# world/run.sh - Agent coordination and event logging

set -euo pipefail

: "${PROJECT_DIR:?PROJECT_DIR not set - source env.sh}"

COMMANDS_DIR="$PROJECT_DIR/world/commands"
WORLD_LOG="$PROJECT_DIR/world/world.log"

show_help() {
    cat <<'HELP'
world - Agent coordination

COMMANDS:
    world                             Show recent log entries
    world ps                          List running task agents (ZFC)
    world record <type> <msg>         Record an event to world.log
    world spawn <task-id>             Start agent in worktree
    world watch [interval]            Run polling daemon (foreground)
    world daemon <cmd>                Shortcut for: daemon world-watch <cmd>

RECORD TYPES:
    system      Daemon/system events
    git:commit  Git commits
    git:merge   Git merges
    error       Errors

EXAMPLES:
    world record "system" "daemon started"
    world record "git:commit" "fix: login bug"
    world ps                          # List running agents

SEE ALSO:
    task help                         Task management
    daemon help                       Daemon management
HELP
}

show_entries() {
    if [ -f "$WORLD_LOG" ]; then
        echo "=== Recent Events ==="
        tail -20 "$WORLD_LOG"
        echo ""
    fi
    show_help
}

# Route
case "${1:-}" in
    ps|processes)
        shift || true
        "$COMMANDS_DIR/ps.sh" "$@"
        ;;
    record)
        shift
        "$COMMANDS_DIR/record.sh" "$@"
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
