#!/usr/bin/env bash
# supervisor/level1.sh
# Level 1 Supervisor: State enforcement - trigger pending tasks

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
WORLD_CMD="$PROJECT_DIR/world/run.sh"
WORLD_LOG="$PROJECT_DIR/world/world.log"
SPAWN_TASK="$SCRIPT_DIR/spawn_task.sh"

# PID management directory
PID_DIR="/tmp/supervisor/pids"
mkdir -p "$PID_DIR"

# Configuration
DRY_RUN="${DRY_RUN:-false}"

show_help() {
    cat <<'EOF'
level1 - Level 1 Supervisor: Trigger pending tasks

USAGE:
    level1.sh [command]

COMMANDS:
    run         Check and trigger pending tasks (default)
    list        List pending tasks without triggering
    check       Check running processes and sync status

DESCRIPTION:
    Reads pending tasks from world.log and checks their trigger conditions.
    Supported triggers:
      - "now"  : Trigger immediately
      - "<datetime>" : Trigger at specific time (YYYY-MM-DDTHH:MM:SS)

    Future triggers (not yet implemented):
      - "after:<task-id>" : Trigger after another task completes

    The 'check' command:
      - Detects crashed processes (PID file exists but process gone)
      - Syncs status to world.log (done/failed)
      - Cleans up worktrees for completed tasks

OPTIONS (via environment):
    DRY_RUN=true    Show what would be done without doing it

EXAMPLES:
    level1.sh              # Run (trigger pending tasks)
    level1.sh list         # Just list pending tasks
    level1.sh check        # Check processes and cleanup
    DRY_RUN=true level1.sh # Dry run mode
EOF
}

# Get pending tasks from world.log
get_pending_tasks() {
    if [ ! -f "$WORLD_LOG" ]; then
        return
    fi

    # Find all pending tasks
    # Format: [timestamp] [task] <id> | pending | <trigger> | <description> | need: <criteria>
    grep '\[task\].*| pending' "$WORLD_LOG" 2>/dev/null || true
}

# Check if a task is already running
is_task_running() {
    local task_id="$1"

    # Check if there's a 'running' entry for this task AFTER the pending entry
    # We look for the most recent status entry for this task
    local last_status
    last_status=$(grep "\[task\] $task_id |" "$WORLD_LOG" | tail -1 | grep -o '| [a-z]*' | head -1 | tr -d '| ' || true)

    if [ "$last_status" = "running" ]; then
        return 0  # true, is running
    fi
    return 1  # false, not running
}

# Check if trigger condition is met
check_trigger() {
    local trigger="$1"

    case "$trigger" in
        now)
            return 0  # Always ready
            ;;
        [0-9][0-9][0-9][0-9]-*)
            # datetime format: YYYY-MM-DDTHH:MM:SS
            local current
            current=$(date -u +"%Y-%m-%dT%H:%M:%S")
            if [[ "$current" > "$trigger" ]] || [[ "$current" == "$trigger" ]]; then
                return 0  # Time has passed
            fi
            echo "  [SKIP] Not yet time (trigger: $trigger, now: $current)"
            return 1
            ;;
        after:*)
            # Future: handle after:<task-id>
            echo "  [SKIP] after:<task-id> trigger not yet implemented"
            return 1
            ;;
        *)
            echo "  [SKIP] Unknown trigger type: $trigger"
            return 1
            ;;
    esac
}

# List pending tasks
list_pending() {
    echo "=== Pending Tasks ==="
    echo ""

    local pending
    pending=$(get_pending_tasks)

    if [ -z "$pending" ]; then
        echo "No pending tasks."
        return
    fi

    echo "$pending" | while IFS= read -r line; do
        # Parse task entry
        local task_id trigger description
        task_id=$(echo "$line" | sed 's/.*\[task\] \([^ ]*\) |.*/\1/')
        trigger=$(echo "$line" | cut -d'|' -f3 | sed 's/^ *//;s/ *$//')
        description=$(echo "$line" | cut -d'|' -f4 | sed 's/^ *//;s/ *$//')

        echo "  [$task_id] trigger=$trigger"
        echo "    $description"

        # Check if running
        if is_task_running "$task_id"; then
            echo "    Status: RUNNING"
        else
            echo "    Status: READY TO SPAWN"
        fi
        echo ""
    done
}

# Run level1 - trigger pending tasks
run_level1() {
    echo "=== Level 1: Triggering Pending Tasks ==="
    echo ""

    local pending
    pending=$(get_pending_tasks)

    if [ -z "$pending" ]; then
        echo "No pending tasks to trigger."
        return
    fi

    local triggered=0
    local skipped=0

    echo "$pending" | while IFS= read -r line; do
        # Parse task entry
        local task_id trigger
        task_id=$(echo "$line" | sed 's/.*\[task\] \([^ ]*\) |.*/\1/')
        trigger=$(echo "$line" | cut -d'|' -f3 | sed 's/^ *//;s/ *$//')

        echo "Checking task: $task_id (trigger: $trigger)"

        # Skip if already running
        if is_task_running "$task_id"; then
            echo "  [SKIP] Already running"
            skipped=$((skipped + 1))
            continue
        fi

        # Check trigger condition
        if ! check_trigger "$trigger"; then
            skipped=$((skipped + 1))
            continue
        fi

        # Trigger the task
        if [ "$DRY_RUN" = "true" ]; then
            echo "  [DRY-RUN] Would spawn task: $task_id"
        else
            echo "  [SPAWN] Spawning task: $task_id"
            "$SPAWN_TASK" "$task_id" &
            # Small delay to avoid race conditions
            sleep 1
        fi

        triggered=$((triggered + 1))
    done

    echo ""
    echo "Summary: triggered=$triggered, skipped=$skipped"
}

# Check running tasks and sync status
check_running_tasks() {
    echo "=== Checking Running Tasks ==="
    echo ""

    local checked=0
    local completed=0
    local crashed=0

    # Iterate over PID files
    for pid_file in "$PID_DIR"/*.pid; do
        # Skip if no files match
        [ -e "$pid_file" ] || continue

        local task_id pid
        task_id=$(basename "$pid_file" .pid)
        pid=$(cat "$pid_file")
        checked=$((checked + 1))

        echo "Checking task: $task_id (PID: $pid)"

        # Check if process is still running
        if kill -0 "$pid" 2>/dev/null; then
            echo "  [RUNNING] Process still active"
            continue
        fi

        echo "  [ENDED] Process no longer running"

        # Check if task reported completion in world.log
        local last_status
        last_status=$(grep "\[task\] $task_id |" "$WORLD_LOG" 2>/dev/null | tail -1 | grep -o '| [a-z]*' | head -1 | tr -d '| ' || true)

        if [ "$last_status" = "done" ]; then
            echo "  [DONE] Task completed successfully"
            completed=$((completed + 1))
        elif [ "$last_status" = "failed" ]; then
            echo "  [FAILED] Task failed (reported by agent)"
            crashed=$((crashed + 1))
        else
            # Process ended without reporting - assume crash
            echo "  [CRASH] Process ended without reporting status"
            if [ "$DRY_RUN" = "true" ]; then
                echo "  [DRY-RUN] Would mark task as failed"
            else
                "$WORLD_CMD" create --task "$task_id" failed
                echo "  [UPDATED] Marked as failed in world.log"
            fi
            crashed=$((crashed + 1))
        fi

        # Clean up PID file
        if [ "$DRY_RUN" = "true" ]; then
            echo "  [DRY-RUN] Would remove PID file"
        else
            rm -f "$pid_file"
            rm -f "$PID_DIR/$task_id.session"
            echo "  [CLEANUP] Removed PID files"
        fi
    done

    echo ""
    echo "Summary: checked=$checked, completed=$completed, crashed=$crashed"
}

# Cleanup worktrees for completed tasks
cleanup_completed_tasks() {
    echo ""
    echo "=== Cleaning Up Completed Tasks ==="
    echo ""

    local cleaned=0

    # Find done/failed tasks in world.log
    for status in done failed; do
        local tasks
        tasks=$(grep "\[task\].*| $status" "$WORLD_LOG" 2>/dev/null | sed 's/.*\[task\] \([^ ]*\) |.*/\1/' | sort -u || true)

        for task_id in $tasks; do
            [ -z "$task_id" ] && continue

            local worktree_path
            worktree_path="$(dirname "$PROJECT_DIR")/claude-code-task-$task_id"

            if [ -d "$worktree_path" ]; then
                echo "Found worktree for $status task: $task_id"
                echo "  Path: $worktree_path"

                if [ "$DRY_RUN" = "true" ]; then
                    echo "  [DRY-RUN] Would remove worktree and branch"
                else
                    # Remove worktree
                    if git -C "$PROJECT_DIR" worktree remove "$worktree_path" --force 2>/dev/null; then
                        echo "  [REMOVED] Worktree removed"
                    else
                        echo "  [WARNING] Failed to remove worktree (may need manual cleanup)"
                    fi

                    # Try to delete the branch
                    if git -C "$PROJECT_DIR" branch -d "task-$task_id" 2>/dev/null; then
                        echo "  [DELETED] Branch task-$task_id deleted"
                    elif git -C "$PROJECT_DIR" branch -D "task-$task_id" 2>/dev/null; then
                        echo "  [DELETED] Branch task-$task_id force-deleted"
                    else
                        echo "  [INFO] Branch task-$task_id not found or already deleted"
                    fi

                    cleaned=$((cleaned + 1))
                fi
            fi
        done
    done

    echo ""
    echo "Cleaned up $cleaned worktrees"
}

# Run check - process detection and cleanup
run_check() {
    check_running_tasks
    cleanup_completed_tasks
}

# Router
case "${1:-run}" in
    run)
        run_level1
        ;;
    list)
        list_pending
        ;;
    check)
        run_check
        ;;
    help|-h|--help)
        show_help
        ;;
    *)
        echo "Unknown command: $1"
        echo "Run 'level1.sh help' for usage"
        exit 1
        ;;
esac
