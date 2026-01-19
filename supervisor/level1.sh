#!/usr/bin/env bash
# supervisor/level1.sh
# Level 1 Supervisor: State enforcement - trigger pending tasks

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
WORLD_LOG="$PROJECT_DIR/world/world.log"
SPAWN_TASK="$SCRIPT_DIR/spawn_task.sh"

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

DESCRIPTION:
    Reads pending tasks from world.log and checks their trigger conditions.
    Currently supported triggers:
      - "now"  : Trigger immediately

    Future triggers (not yet implemented):
      - "<datetime>" : Trigger at specific time
      - "after:<task-id>" : Trigger after another task completes

OPTIONS (via environment):
    DRY_RUN=true    Show what would be done without doing it

EXAMPLES:
    level1.sh              # Run (trigger pending tasks)
    level1.sh list         # Just list pending tasks
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
        *)
            # Future: handle datetime and after:<task-id>
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

# Router
case "${1:-run}" in
    run)
        run_level1
        ;;
    list)
        list_pending
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
