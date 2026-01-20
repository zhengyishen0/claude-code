#!/bin/bash
# SessionEnd hook: Update task status when agent finishes
set -eo pipefail

# Read hook input
input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id // empty')
cwd=$(echo "$input" | jq -r '.cwd // empty')

# Use env vars (set by spawn.sh) or defaults
: "${PID_DIR:=/tmp/world/pids}"

# Only process if this is a task agent
if [ "$AGENT_TYPE" != "task" ]; then
    exit 0
fi

# Need TASK_FILE to update
if [ -z "$TASK_FILE" ] || [ ! -f "$TASK_FILE" ]; then
    exit 0
fi

# Check if yq is available
if ! command -v yq >/dev/null 2>&1; then
    exit 0
fi

# Read current status
current_status=$(yq eval --front-matter=extract '.status' "$TASK_FILE" 2>/dev/null || echo "")
task_id=$(yq eval --front-matter=extract '.id' "$TASK_FILE" 2>/dev/null || echo "")

# Only update if still running (agent didn't set final status)
if [ "$current_status" = "running" ]; then
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Mark as done (agent completed without explicit status change)
    yq -i --front-matter=process '.status = "done"' "$TASK_FILE"
    yq -i --front-matter=process ".completed = \"$timestamp\"" "$TASK_FILE"
    
    echo "Task $task_id marked as done"
fi

# Clean up PID file
if [ -n "${PID_DIR:-}" ]; then
    rm -f "$PID_DIR/$task_id.pid" 2>/dev/null || true
else
    rm -f "/tmp/world/pids/$task_id.pid" 2>/dev/null || true
fi

exit 0
