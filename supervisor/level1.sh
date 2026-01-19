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

# Get pending tasks from markdown files
get_pending_tasks() {
    local tasks_dir="$PROJECT_DIR/tasks"
    [ -d "$tasks_dir" ] || return

    # Ensure yq is installed
    if ! command -v yq >/dev/null 2>&1; then
        return
    fi

    # Find all pending tasks in markdown files
    for md_file in "$tasks_dir"/*.md; do
        [ -e "$md_file" ] || continue

        local status
        status=$(yq eval --front-matter=extract '.status' "$md_file" 2>/dev/null || echo "")

        if [ "$status" = "pending" ]; then
            echo "$md_file"
        fi
    done
}

# Check if a task is already running
is_task_running() {
    local task_id="$1"
    local task_md="$PROJECT_DIR/tasks/$task_id.md"

    [ -f "$task_md" ] || return 1

    if ! command -v yq >/dev/null 2>&1; then
        return 1
    fi

    local status
    status=$(yq eval --front-matter=extract '.status' "$task_md" 2>/dev/null || echo "")

    if [ "$status" = "running" ]; then
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

    if ! command -v yq >/dev/null 2>&1; then
        echo "Error: yq not installed. Install with: brew install yq"
        return
    fi

    echo "$pending" | while IFS= read -r md_file; do
        # Parse task from markdown
        local task_id title wait
        task_id=$(yq eval --front-matter=extract '.id' "$md_file" 2>/dev/null || echo "")
        title=$(yq eval --front-matter=extract '.title' "$md_file" 2>/dev/null || echo "Untitled")
        wait=$(yq eval --front-matter=extract '.wait // "-"' "$md_file" 2>/dev/null || echo "-")

        echo "  [$task_id] wait=$wait"
        echo "    $title"

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

    if ! command -v yq >/dev/null 2>&1; then
        echo "Error: yq not installed. Install with: brew install yq"
        return
    fi

    local triggered=0
    local skipped=0

    echo "$pending" | while IFS= read -r md_file; do
        # Parse task from markdown
        local task_id wait
        task_id=$(yq eval --front-matter=extract '.id' "$md_file" 2>/dev/null || echo "")
        wait=$(yq eval --front-matter=extract '.wait // "-"' "$md_file" 2>/dev/null || echo "-")

        echo "Checking task: $task_id (wait: $wait)"

        # Skip if already running
        if is_task_running "$task_id"; then
            echo "  [SKIP] Already running"
            skipped=$((skipped + 1))
            continue
        fi

        # Check trigger condition (convert wait to trigger for compatibility)
        # For now, treat "-" as "now", other values need to be parsed
        local trigger="$wait"
        if [ "$wait" = "-" ]; then
            trigger="now"
        fi

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

        # Check task status from markdown file
        local task_md="$PROJECT_DIR/tasks/$task_id.md"
        local last_status=""

        if [ -f "$task_md" ] && command -v yq >/dev/null 2>&1; then
            last_status=$(yq eval --front-matter=extract '.status' "$task_md" 2>/dev/null || echo "")
        fi

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
                if [ -f "$task_md" ] && command -v yq >/dev/null 2>&1; then
                    yq -i '.status = "failed"' "$task_md"
                    yq -i ".failed = \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"" "$task_md"
                    yq -i '.result = "Process crashed without reporting status"' "$task_md"
                    echo "  [UPDATED] Marked as failed in $task_md"
                else
                    echo "  [WARNING] Could not update task file (yq not installed or file missing)"
                fi
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

# Cleanup worktrees for verified/canceled tasks
cleanup_completed_tasks() {
    echo ""
    echo "=== Cleaning Up Verified/Canceled Tasks ==="
    echo ""

    local cleaned=0
    local tasks_dir="$PROJECT_DIR/tasks"

    # Ensure yq is installed
    if ! command -v yq >/dev/null 2>&1; then
        echo "Warning: yq not installed. Skipping cleanup."
        echo "Install with: brew install yq"
        return
    fi

    # Only clean up verified and canceled tasks
    for status in verified canceled; do
        # Find all task markdown files
        for md_file in "$tasks_dir"/*.md; do
            [ -e "$md_file" ] || continue

            local task_id file_status
            task_id=$(yq eval --front-matter=extract '.id' "$md_file" 2>/dev/null || echo "")
            file_status=$(yq eval --front-matter=extract '.status' "$md_file" 2>/dev/null || echo "")

            [ -z "$task_id" ] && continue
            [ "$file_status" != "$status" ] && continue

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
