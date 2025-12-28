#!/bin/bash
# SessionStart hook: Display session info
set -eo pipefail

# Read hook input with session_id and cwd
input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id')
cwd=$(echo "$input" | jq -r '.cwd')

# Debug: write to file to verify hook runs
echo "[$(date)] Hook executed - Session: $session_id" >> /tmp/claude-hook-debug.log

# Show session info and git branch
echo ""
echo "📋 Session ID: $session_id"

if [ -d "$cwd/.git" ] || git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
  current_branch=$(git -C "$cwd" branch --show-current 2>/dev/null || echo "unknown")
  echo "📍 Current branch: $current_branch"

  if [ "$current_branch" = "main" ]; then
    echo "⚠️  WARNING: On main branch! Create a worktree before making ANY changes:"
    echo "   claude-tools worktree create <feature-name>"
  fi
fi

echo ""

exit 0
