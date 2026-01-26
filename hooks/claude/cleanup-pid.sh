#!/bin/bash
# Clean up PID file when agent finishes
# Hook: SessionEnd
# Requires: AGENT_TYPE=task, TASK_FILE
set -eo pipefail

# Only for task agents
if [ "$AGENT_TYPE" != "task" ]; then
  exit 0
fi

# Use env var or default
: "${PID_DIR:=/tmp/world-watch/pids}"

# Need TASK_FILE to get task ID
if [ -z "$TASK_FILE" ] || [ ! -f "$TASK_FILE" ]; then
  exit 0
fi

task_id=$(yq eval --front-matter=extract '.id' "$TASK_FILE" 2>/dev/null || echo "")

# Clean up PID file
if [ -n "$task_id" ]; then
  rm -f "$PID_DIR/$task_id.pid" 2>/dev/null || true
fi

exit 0
