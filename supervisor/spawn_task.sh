#!/usr/bin/env bash
# supervisor/spawn_task.sh
# Spawn a task agent in a dedicated worktree

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
WORLD_CMD="$PROJECT_DIR/world/run.sh"
WORLD_LOG="$PROJECT_DIR/world/world.log"

show_help() {
    cat <<'EOF'
spawn_task - Create worktree and start claude for a task

USAGE:
    spawn_task.sh <task-id>

DESCRIPTION:
    1. Reads task info from world.log
    2. Creates git worktree: ../claude-code-task-<id>
    3. Sets environment variables for the agent
    4. Updates task status to 'running'
    5. Starts claude with --print mode

ENVIRONMENT VARIABLES SET:
    AGENT_TYPE=task
    AGENT_SESSION_ID=<task-id>
    AGENT_DESCRIPTION=<task description>
    CLAUDE_PROJECT_DIR=<worktree path>

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

# Check if world.log exists
if [ ! -f "$WORLD_LOG" ]; then
    echo "Error: world.log not found at $WORLD_LOG"
    exit 1
fi

# Find the most recent pending entry for this task
task_entry=$(grep "\[task\] $task_id | pending" "$WORLD_LOG" | tail -1 || true)

if [ -z "$task_entry" ]; then
    echo "Error: No pending task found with id '$task_id'"
    echo "Run 'world check --task --status pending' to see pending tasks"
    exit 1
fi

# Parse task entry
# Format: [timestamp] [task] <id> | <status> | <trigger> | <description> | need: <criteria>
# Extract description (4th field after splitting by |)
task_description=$(echo "$task_entry" | cut -d'|' -f4 | sed 's/^ *//;s/ *$//')
task_need=$(echo "$task_entry" | grep -o 'need: .*' | sed 's/need: //' || true)

if [ -z "$task_description" ]; then
    task_description="Task $task_id"
fi

echo "=== Spawning Task: $task_id ==="
echo "Description: $task_description"
[ -n "$task_need" ] && echo "Success criteria: $task_need"
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
"$WORLD_CMD" create --task "$task_id" running

# Build prompt for claude
prompt="You are a task agent.

Task ID: $task_id
Description: $task_description"

if [ -n "$task_need" ]; then
    prompt="$prompt
Success Criteria: $task_need"
fi

prompt="$prompt

When done, report completion with:
  world create --task $task_id done

If you encounter a blocker, report failure with:
  world create --task $task_id failed"

echo ""
echo "Starting claude agent..."
echo "---"

# Start claude with environment variables
export AGENT_TYPE="task"
export AGENT_SESSION_ID="$task_id"
export AGENT_DESCRIPTION="$task_description"
export CLAUDE_PROJECT_DIR="$worktree_path"

# Run claude
exec claude --print --cwd "$worktree_path" "$prompt"
