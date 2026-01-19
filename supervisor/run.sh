#!/usr/bin/env bash
# supervisor/run.sh
# Supervisor system - orchestrate task agents

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPAWN_TASK="$SCRIPT_DIR/spawn_task.sh"
LEVEL1="$SCRIPT_DIR/level1.sh"
MD_WATCHER="$SCRIPT_DIR/md_watcher.sh"

show_help() {
    cat <<'EOF'
supervisor - Orchestrate task agents

USAGE:
    supervisor                   Show this help
    supervisor spawn <task-id>   Manually spawn a task agent
    supervisor verify <task-id>  Verify completed task (marks as verified)
    supervisor cancel <task-id>  Cancel task (marks as canceled)
    supervisor level1 [command]  Run Level 1 supervisor
    supervisor check             Check processes and cleanup
    supervisor once              Run all supervisor levels once
    supervisor daemon [interval] Run continuously (default: 30s)

COMMANDS:
    spawn <task-id>
        Create a worktree and start claude for the specified task.
        The task must exist in tasks/<id>.md with status 'pending'.

    verify <task-id>
        Mark a completed task as verified. This allows the supervisor
        to clean up the worktree.

    cancel <task-id>
        Cancel a task. This marks the task as canceled and allows
        the supervisor to clean up the worktree.

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

    # Start md_watcher in background
    echo "Starting MD watcher..."
    "$MD_WATCHER" &
    local watcher_pid=$!
    echo "MD watcher started (PID: $watcher_pid)"
    echo ""

    # Setup trap to kill watcher on exit
    trap 'echo ""; echo "Stopping..."; kill $watcher_pid 2>/dev/null; echo "Daemon stopped."; exit 0' INT TERM

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
    verify)
        shift
        if [ $# -lt 1 ]; then
            echo "Error: verify requires <task-id>"
            echo "Usage: supervisor verify <task-id>"
            exit 1
        fi
        task_id="$1"
        task_file="$SCRIPT_DIR/../tasks/$task_id.md"
        if [ ! -f "$task_file" ]; then
            echo "Error: Task file not found: $task_file"
            exit 1
        fi
        # Ensure yq is installed
        if ! command -v yq >/dev/null 2>&1; then
            echo "Error: yq not installed. Install with: brew install yq"
            exit 1
        fi
        yq -i --front-matter=process '.status = "verified"' "$task_file"
        yq -i --front-matter=process ".verified = \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"" "$task_file"
        echo "✓ Task verified: $task_id"
        ;;
    cancel)
        shift
        if [ $# -lt 1 ]; then
            echo "Error: cancel requires <task-id>"
            echo "Usage: supervisor cancel <task-id>"
            exit 1
        fi
        task_id="$1"
        task_file="$SCRIPT_DIR/../tasks/$task_id.md"
        if [ ! -f "$task_file" ]; then
            echo "Error: Task file not found: $task_file"
            exit 1
        fi
        # Ensure yq is installed
        if ! command -v yq >/dev/null 2>&1; then
            echo "Error: yq not installed. Install with: brew install yq"
            exit 1
        fi
        yq -i --front-matter=process '.status = "canceled"' "$task_file"
        yq -i --front-matter=process ".canceled = \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"" "$task_file"
        echo "✓ Task canceled: $task_id"
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
