#!/usr/bin/env bash
# world/commands/spawn.sh
# Spawn a task agent in a dedicated worktree

set -euo pipefail

: "${PROJECT_DIR:?PROJECT_DIR not set - source env.sh}"

TASKS_DIR="$PROJECT_DIR/task/data"
PID_DIR="/tmp/world-watch/pids"
PROJECT_WORKTREES="$(dirname "$PROJECT_DIR")/.worktrees/$(basename "$PROJECT_DIR")"


show_help() {
    cat <<'EOF'
spawn - Start a task agent in a dedicated worktree

USAGE:
    spawn <task-id>

DESCRIPTION:
    1. Reads task from task/data/<id>.md
    2. Creates worktree: ~/Codes/.worktrees/<project>/<task-id>
    3. Updates status to 'running', sets 'started' timestamp
    4. Starts claude with --session-id (preserves context)
    5. Saves PID for monitoring

EXAMPLES:
    world spawn fix-bug
    world spawn feature-123
EOF
}

if [ $# -lt 1 ] || [ "${1:-}" = "help" ] || [ "${1:-}" = "-h" ]; then
    show_help
    exit 0
fi

task_id="$1"

# Check task file exists
task_md="$TASKS_DIR/$task_id.md"
if [ ! -f "$task_md" ]; then
    echo "Error: Task not found: $task_md" >&2
    echo "Create with: world create --task <id> <title>" >&2
    exit 1
fi

# Read task info
session_id=$(yq eval --front-matter=extract '.session_id' "$task_md" 2>/dev/null || echo "")
title=$(yq eval --front-matter=extract '.title' "$task_md" 2>/dev/null || echo "Untitled")
status=$(yq eval --front-matter=extract '.status' "$task_md" 2>/dev/null || echo "")
wait=$(yq eval --front-matter=extract '.wait // "-"' "$task_md" 2>/dev/null || echo "-")
need=$(yq eval --front-matter=extract '.need // "-"' "$task_md" 2>/dev/null || echo "-")

if [ -z "$session_id" ]; then
    echo "Error: Invalid task file (missing session_id)" >&2
    exit 1
fi

if [ "$status" != "pending" ]; then
    echo "Error: Task '$task_id' is not pending (status: $status)" >&2
    exit 1
fi

# Check if already running
mkdir -p "$PID_DIR"
if [ -f "$PID_DIR/$task_id.pid" ]; then
    pid=$(cat "$PID_DIR/$task_id.pid")
    if kill -0 "$pid" 2>/dev/null; then
        echo "Error: Task '$task_id' already running (PID: $pid)" >&2
        exit 1
    fi
    # Stale PID file, remove it
    rm -f "$PID_DIR/$task_id.pid"
fi

echo "=== Spawning Task: $task_id ==="
echo "Title: $title"
echo "Session: $session_id"
[ "$wait" != "-" ] && echo "Wait: $wait"
[ "$need" != "-" ] && echo "Need: $need"
echo ""

# Worktree setup
worktree_path="$PROJECT_WORKTREES/$task_id"
mkdir -p "$PROJECT_WORKTREES"

if [ -d "$worktree_path" ]; then
    echo "Reusing existing worktree: $worktree_path"
else
    echo "Creating worktree: $worktree_path"
    git -C "$PROJECT_DIR" worktree add -b "task-$task_id" "$worktree_path" 2>/dev/null || \
    git -C "$PROJECT_DIR" worktree add "$worktree_path" "task-$task_id" 2>/dev/null || {
        echo "Error: Failed to create worktree" >&2
        exit 1
    }
fi

# Update task status
timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
yq -i --front-matter=process '.status = "running"' "$task_md"
yq -i --front-matter=process ".started = \"$timestamp\"" "$task_md"

# System prompt from markdown file
prompt_file="$PROJECT_DIR/world/agent-prompt.md"
if [ ! -f "$prompt_file" ]; then
    echo "Error: Agent prompt file not found: $prompt_file" >&2
    exit 1
fi
system_prompt=$(sed "s|{{TASK_FILE}}|$task_md|g" "$prompt_file")

# Task prompt (specific task to execute)
task_prompt="Execute this task:

Title: $title
Wait: $wait
Need: $need

Start by reading the task file, then proceed with the work."

echo "Starting claude..."
echo "---"

# Set environment
export AGENT_TYPE="task"
export AGENT_SESSION_ID="$session_id"
export TASK_FILE="$task_md"
export CLAUDE_PROJECT_DIR="$worktree_path"

# Start claude with appended system prompt
(cd "$worktree_path" && claude \
    --dangerously-skip-permissions \
    --print \
    --session-id "$session_id" \
    --append-system-prompt "$system_prompt" \
    "$task_prompt") &
CLAUDE_PID=$!

# Save PID
echo "$CLAUDE_PID" > "$PID_DIR/$task_id.pid"

echo "Spawned with PID: $CLAUDE_PID"
echo "PID file: $PID_DIR/$task_id.pid"

# Wait for completion
wait $CLAUDE_PID || true
