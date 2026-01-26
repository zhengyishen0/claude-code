#!/bin/bash
# Update task status when agent finishes
# Hook: SessionEnd
# Requires: AGENT_TYPE=task, TASK_FILE
set -eo pipefail

# Only for task agents
if [ "$AGENT_TYPE" != "task" ]; then
  exit 0
fi

# Need TASK_FILE to update
if [ -z "$TASK_FILE" ] || [ ! -f "$TASK_FILE" ]; then
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

exit 0
