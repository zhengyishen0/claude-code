#!/bin/bash
# SessionEnd hook: Update task status and report to world.log
set -eo pipefail

# Read hook input
input=$(cat)
cwd=$(echo "$input" | jq -r '.cwd')
exit_code=$(echo "$input" | jq -r '.exit_code')

# Check if this is a Task Agent session
if [ -z "$TASK_FILE" ] || [ ! -f "$TASK_FILE" ]; then
  exit 0
fi

cd "$cwd" || exit 0

# Ensure yq is available
if ! command -v yq >/dev/null 2>&1; then
  exit 0
fi

# Read current task status
task_id=$(yq '.id' "$TASK_FILE" 2>/dev/null || echo "")
status=$(yq '.status' "$TASK_FILE" 2>/dev/null || echo "")
title=$(yq '.title' "$TASK_FILE" 2>/dev/null || echo "")

if [ -z "$task_id" ]; then
  exit 0
fi

# Update task based on status when session ended
if [ "$status" = "running" ]; then
  # Session ended while still running = crashed/failed
  yq -i --front-matter=process '.status = "failed"' "$TASK_FILE" 2>/dev/null || true
  yq -i --front-matter=process ".completed = \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"" "$TASK_FILE" 2>/dev/null || true
  yq -i --front-matter=process '.result = "Session ended unexpectedly"' "$TASK_FILE" 2>/dev/null || true
elif [ "$status" = "done" ]; then
  # Session ended with done status = successful completion
  # Update completed timestamp if not already set
  completed=$(yq '.completed' "$TASK_FILE" 2>/dev/null || echo "null")
  if [ "$completed" = "null" ]; then
    yq -i --front-matter=process ".completed = \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"" "$TASK_FILE" 2>/dev/null || true
  fi
fi

# Clean up PID file
if [ -n "$task_id" ]; then
  rm -f "/tmp/supervisor/pids/$task_id.pid" 2>/dev/null || true
fi

exit 0
