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
    supervisor once              Run all supervisor levels once

COMMANDS:
    spawn <task-id>
        Create a worktree and start claude for the specified task.
        The task must exist in world.log with status 'pending'.

    level1 [run|list]
        Level 1: State enforcement
        - 'run' (default): Check pending tasks and spawn those ready
        - 'list': Show pending tasks without spawning

    once
        Run all supervisor levels once:
        - Level 1: Trigger pending tasks with met conditions

OPTIONS (via environment):
    DRY_RUN=true    Show what would be done without doing it

EXAMPLES:
    supervisor                      # Show help
    supervisor spawn login-fix      # Spawn task 'login-fix'
    supervisor level1               # Run level1 (trigger pending)
    supervisor level1 list          # List pending tasks
    supervisor once                 # Run all levels once
    DRY_RUN=true supervisor once    # Dry run all levels

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

    echo ">>> Level 1: Trigger Pending Tasks"
    DRY_RUN="${DRY_RUN:-false}" "$LEVEL1" run
    echo ""

    echo "=== Done ==="
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
    once)
        run_once
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
