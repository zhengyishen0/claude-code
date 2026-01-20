#!/usr/bin/env bash
# supervisor/run.sh
# L2 Supervisor - verify, cancel, retry tasks

set -euo pipefail

: "${PROJECT_DIR:?PROJECT_DIR not set - source env.sh}"

TASKS_DIR="$PROJECT_DIR/tasks"
PID_DIR="/tmp/world-watch/pids"
PROJECT_WORKTREES="$(dirname "$PROJECT_DIR")/.worktrees/$(basename "$PROJECT_DIR")"
PROJECT_ARCHIVE="$PROJECT_WORKTREES/.archive"

# Get supervisor session ID (generate if not set)
SUPERVISOR_SESSION="${SUPERVISOR_SESSION_ID:-$(uuidgen | tr '[:upper:]' '[:lower:]')}"

show_help() {
    cat <<'EOF'
supervisor - L2 Supervisor: verify, cancel, retry tasks

USAGE:
    supervisor verify <task-id>    Mark task as verified
    supervisor cancel <task-id>    Cancel task
    supervisor retry <task-id>     Retry task (restore from archive if needed)

DESCRIPTION:
    L2 supervisor provides approval actions for completed tasks.
    These commands update the 'review' field in task markdown:
    
        review: verified | <supervisor-session>
        review: canceled | <supervisor-session>
        review: retry | <supervisor-session>

    The world watch daemon detects these changes and:
    - Archives worktrees for verified/canceled
    - Re-spawns for retry

WORKTREE STRUCTURE:
    $PROJECT_WORKTREES/
    ├── <active-worktrees>/
    └── .archive/
        └── <archived-worktrees>/

EXAMPLES:
    supervisor verify fix-bug
    supervisor cancel feature-x
    supervisor retry failed-task
EOF
}

# Verify a completed task
do_verify() {
    local task_id="$1"
    local task_md="$TASKS_DIR/$task_id.md"

    if [ ! -f "$task_md" ]; then
        echo "Error: Task not found: $task_md" >&2
        exit 1
    fi

    local status=$(yq eval --front-matter=extract '.status' "$task_md" 2>/dev/null || echo "")

    if [ "$status" != "done" ]; then
        echo "Error: Task '$task_id' is not done (status: $status)" >&2
        echo "Only completed tasks can be verified." >&2
        exit 1
    fi

    # Set review field
    yq -i --front-matter=process ".review = \"verified | $SUPERVISOR_SESSION\"" "$task_md"

    echo "✓ Task verified: $task_id"
    echo "  review: verified | $SUPERVISOR_SESSION"
}

# Cancel a task
do_cancel() {
    local task_id="$1"
    local task_md="$TASKS_DIR/$task_id.md"

    if [ ! -f "$task_md" ]; then
        echo "Error: Task not found: $task_md" >&2
        exit 1
    fi

    # Kill if running
    local pid_file="$PID_DIR/$task_id.pid"
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            echo "Killing running process (PID: $pid)..."
            kill "$pid" 2>/dev/null || true
        fi
        rm -f "$pid_file"
    fi

    # Set review field
    yq -i --front-matter=process ".review = \"canceled | $SUPERVISOR_SESSION\"" "$task_md"

    echo "✓ Task canceled: $task_id"
    echo "  review: canceled | $SUPERVISOR_SESSION"
}

# Retry a task
do_retry() {
    local task_id="$1"
    local task_md="$TASKS_DIR/$task_id.md"

    if [ ! -f "$task_md" ]; then
        echo "Error: Task not found: $task_md" >&2
        exit 1
    fi

    local worktree_path="$PROJECT_WORKTREES/$task_id"
    
    if [ ! -d "$worktree_path" ]; then
        # Look for archived worktree
        local archived=$(ls -d "$PROJECT_ARCHIVE"/$task_id-* 2>/dev/null | tail -1 || echo "")
        
        if [ -n "$archived" ] && [ -d "$archived" ]; then
            echo "Restoring from archive: $archived"
            mkdir -p "$PROJECT_WORKTREES"
            mv "$archived" "$worktree_path"
            git -C "$PROJECT_DIR" worktree repair "$worktree_path" 2>/dev/null || true
        fi
    fi

    # Reset status to pending and set review
    yq -i --front-matter=process '.status = "pending"' "$task_md"
    yq -i --front-matter=process ".review = \"retry | $SUPERVISOR_SESSION\"" "$task_md"
    
    # Clear timestamps
    yq -i --front-matter=process 'del(.completed)' "$task_md" 2>/dev/null || true
    yq -i --front-matter=process 'del(.started)' "$task_md" 2>/dev/null || true

    echo "✓ Task queued for retry: $task_id"
    echo "  review: retry | $SUPERVISOR_SESSION"
    echo "  status: pending"
    echo ""
    echo "The watch daemon will spawn this task."
}

# Parse arguments
if [ $# -lt 1 ]; then
    show_help
    exit 0
fi

case "$1" in
    verify)
        [ $# -lt 2 ] && { echo "Error: verify requires <task-id>" >&2; exit 1; }
        do_verify "$2"
        ;;
    cancel)
        [ $# -lt 2 ] && { echo "Error: cancel requires <task-id>" >&2; exit 1; }
        do_cancel "$2"
        ;;
    retry)
        [ $# -lt 2 ] && { echo "Error: retry requires <task-id>" >&2; exit 1; }
        do_retry "$2"
        ;;
    help|-h|--help)
        show_help
        ;;
    *)
        echo "Unknown command: $1" >&2
        echo "Run 'supervisor help' for usage" >&2
        exit 1
        ;;
esac
