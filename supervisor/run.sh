#!/usr/bin/env bash
# supervisor/run.sh
# Supervisor system - orchestrate task agents

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPAWN_TASK="$SCRIPT_DIR/spawn_task.sh"
LEVEL1="$SCRIPT_DIR/level1.sh"

show_help() {
    cat <<'EOF'
supervisor - Orchestrate task agents

USAGE:
    supervisor                   Show this help
    supervisor spawn <task-id>   Manually spawn a task agent
    supervisor level1 [command]  Run Level 1 supervisor
    supervisor check             Check processes and cleanup
    supervisor once              Run all supervisor levels once
    supervisor daemon [interval] Run continuously (default: 30s)

COMMANDS:
    spawn <task-id>
        Create a worktree and start claude for the specified task.
        The task must exist in world.log with status 'pending'.

    level1 [run|list|check]
        Level 1: State enforcement
        - 'run' (default): Check pending tasks and spawn those ready
        - 'list': Show pending tasks without spawning
        - 'check': Check running processes and cleanup

    check
        Shortcut for 'level1 check':
        - Detect crashed processes (PID exists but process gone)
        - Sync status to world.log (mark crashed as failed)
        - Cleanup worktrees for done/failed tasks

    once
        Run all supervisor levels once:
        - Level 1: Trigger pending tasks with met conditions

    daemon [interval]
        Run supervisor continuously in a loop.
        Default interval: 30 seconds.
        Each iteration runs: check + once

OPTIONS (via environment):
    DRY_RUN=true    Show what would be done without doing it

EXAMPLES:
    supervisor                      # Show help
    supervisor spawn login-fix      # Spawn task 'login-fix'
    supervisor level1               # Run level1 (trigger pending)
    supervisor level1 list          # List pending tasks
    supervisor check                # Check processes and cleanup
    supervisor once                 # Run all levels once
    DRY_RUN=true supervisor once    # Dry run all levels
    supervisor daemon               # Run continuously (30s interval)
    supervisor daemon 10            # Run continuously (10s interval)

WORKFLOW:
    1. Create a task:
       world create --task my-task pending now "Fix the bug" --need "tests pass"

    2. Spawn the task (manual):
       supervisor spawn my-task

    3. Or let the supervisor trigger it:
       supervisor once

ARCHITECTURE:
    supervisor/
    ├── run.sh          # This file - main entry point
    ├── spawn_task.sh   # Create worktree + start claude
    └── level1.sh       # Trigger pending tasks

    Each spawned task runs in its own worktree:
    ../claude-code-task-<id>/
EOF
}

run_once() {
    echo "=== Running Supervisor (once) ==="
    echo ""

    echo ">>> Checking processes and cleanup"
    "$LEVEL1" check
    echo ""

    echo ">>> Level 1: Trigger Pending Tasks"
    DRY_RUN="${DRY_RUN:-false}" "$LEVEL1" run
    echo ""

    echo "=== Done ==="
}

run_daemon() {
    local interval="${1:-30}"
    echo "=== Supervisor Daemon ==="
    echo "Interval: ${interval}s"
    echo "Press Ctrl+C to stop"
    echo ""

    trap 'echo ""; echo "Daemon stopped."; exit 0' INT TERM

    while true; do
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Running supervisor..."
        run_once
        echo ""
        echo "Sleeping ${interval}s..."
        sleep "$interval"
    done
}

# No args = help
if [ $# -lt 1 ]; then
    show_help
    exit 0
fi

# Router
case "$1" in
    spawn)
        shift
        if [ $# -lt 1 ]; then
            echo "Error: spawn requires <task-id>"
            echo "Usage: supervisor spawn <task-id>"
            exit 1
        fi
        "$SPAWN_TASK" "$@"
        ;;
    level1)
        shift
        "$LEVEL1" "${@:-run}"
        ;;
    check)
        "$LEVEL1" check
        ;;
    once)
        run_once
        ;;
    daemon)
        shift
        run_daemon "${1:-30}"
        ;;
    help|-h|--help)
        show_help
        ;;
    *)
        echo "Unknown command: $1"
        echo "Run 'supervisor help' for usage"
        exit 1
        ;;
esac
