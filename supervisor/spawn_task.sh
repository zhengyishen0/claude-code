#!/usr/bin/env bash
# supervisor/spawn_task.sh
# Spawn a task agent in a dedicated worktree

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
WORLD_CMD="$PROJECT_DIR/world/run.sh"
WORLD_LOG="$PROJECT_DIR/world/world.log"

# PID management directory
PID_DIR="/tmp/supervisor/pids"
mkdir -p "$PID_DIR"

show_help() {
    cat <<'EOF'
spawn_task - Create worktree and start claude for a task

USAGE:
    spawn_task.sh <task-id>

DESCRIPTION:
    1. Reads task info from tasks/<id>.md
    2. Creates git worktree: ../claude-code-task-<id>
    3. Sets environment variables for the agent
    4. Updates task status to 'running' in markdown file
    5. Starts claude with --print mode

ENVIRONMENT VARIABLES SET:
    AGENT_TYPE=task
    AGENT_SESSION_ID=<session-id from md file>
    AGENT_DESCRIPTION=<task title>
    CLAUDE_PROJECT_DIR=<worktree path>
    TASK_FILE=<path to tasks/<id>.md>

EXAMPLES:
    spawn_task.sh login-fix
    spawn_task.sh feature-123
EOF
}

# No args = help
if [ $# -lt 1 ] || [ "${1:-}" = "help" ] || [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    show_help
    exit 0
fi

task_id="$1"

# Ensure yq is installed
if ! command -v yq >/dev/null 2>&1; then
    echo "Error: yq not installed. Install with: brew install yq"
    exit 1
fi

# Check if task markdown file exists
task_md="$PROJECT_DIR/tasks/$task_id.md"
if [ ! -f "$task_md" ]; then
    echo "Error: Task file not found: $task_md"
    echo "Create task with: world create --task <id> <title>"
    exit 1
fi

# Read task info from markdown frontmatter
session_id=$(yq eval --front-matter=extract '.session_id' "$task_md" 2>/dev/null || echo "")
title=$(yq eval --front-matter=extract '.title' "$task_md" 2>/dev/null || echo "Untitled")
status=$(yq eval --front-matter=extract '.status' "$task_md" 2>/dev/null || echo "pending")
wait=$(yq eval --front-matter=extract '.wait // "-"' "$task_md" 2>/dev/null || echo "-")
need=$(yq eval --front-matter=extract '.need // "-"' "$task_md" 2>/dev/null || echo "-")

if [ -z "$session_id" ]; then
    echo "Error: Invalid task file (missing session_id)"
    exit 1
fi

if [ "$status" != "pending" ]; then
    echo "Error: Task '$task_id' is not pending (current status: $status)"
    exit 1
fi

echo "=== Spawning Task: $task_id ==="
echo "Title: $title"
echo "Session ID: $session_id"
echo "Wait: $wait"
[ "$need" != "-" ] && echo "Success criteria: $need"
echo ""

# Determine worktree path
worktree_name="claude-code-task-$task_id"
worktree_path="$(dirname "$PROJECT_DIR")/$worktree_name"

# Check if worktree already exists
if [ -d "$worktree_path" ]; then
    echo "Warning: Worktree already exists at $worktree_path"
    echo "Reusing existing worktree..."
else
    # Create worktree
    echo "Creating worktree at $worktree_path..."
    git -C "$PROJECT_DIR" worktree add -b "task-$task_id" "$worktree_path" 2>/dev/null || {
        # Branch might already exist, try without -b
        git -C "$PROJECT_DIR" worktree add "$worktree_path" "task-$task_id" 2>/dev/null || {
            echo "Error: Failed to create worktree"
            exit 1
        }
    }
    echo "Worktree created."
fi

# Update task status to running
echo "Updating task status to 'running'..."
yq -i --front-matter=process '.status = "running"' "$task_md"
yq -i --front-matter=process ".started = \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"" "$task_md"

# Build prompt for claude
prompt="You are a task agent.

Your task information is in: $task_md

IMPORTANT: Read this file to understand:
1. Your task ID: $task_id
2. Task title: $title
3. Wait condition: $wait
4. Success criteria: $need

WORKFLOW:
1. Read the task markdown file using the Read tool
2. Understand the frontmatter (id, title, wait, need)
3. If wait != \"-\", implement wait logic (e.g., check if dependency task is done)
4. Execute the task steps
5. When complete, update the markdown file:
   - Set status to 'done'
   - Add 'completed' timestamp
   - Add 'result' field with summary
   - Add a '## Task Report' section at the end

Do NOT use world create commands. Just edit the markdown file directly.
The MD watcher will automatically sync status changes to world.log."

echo ""
echo "Starting claude agent..."
echo "---"

# Start claude with environment variables
export AGENT_TYPE="task"
export AGENT_SESSION_ID="$session_id"
export AGENT_DESCRIPTION="$title"
export CLAUDE_PROJECT_DIR="$worktree_path"
export TASK_FILE="$task_md"

# Run claude in background and save PID
claude --print --session-id "$session_id" --cwd "$worktree_path" "$prompt" &
CLAUDE_PID=$!

# Save PID file
echo "$CLAUDE_PID" > "$PID_DIR/$task_id.pid"

# Save session info (task_id, worktree_path, title)
cat > "$PID_DIR/$task_id.session" <<EOF
task_id=$task_id
session_id=$session_id
worktree_path=$worktree_path
title=$title
task_file=$task_md
started_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF

echo "Task spawned with PID: $CLAUDE_PID"
echo "PID file: $PID_DIR/$task_id.pid"

# Wait for the process to complete
wait $CLAUDE_PID || true
