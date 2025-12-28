#!/bin/bash
# SessionStart hook: Display session info and write session ID for memory tools
set -eo pipefail

# Read hook input with session_id and cwd
input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id')
cwd=$(echo "$input" | jq -r '.cwd')

# Write session ID to file for memory tools to exclude current session
if [ -n "$session_id" ]; then
  mkdir -p ~/.claude
  echo "$session_id" > ~/.claude/current-session-id
fi

# Show session info and git branch
echo "" >&2
echo "📋 Session ID: $session_id" >&2

if [ -d "$cwd/.git" ] || git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
  current_branch=$(git -C "$cwd" branch --show-current 2>/dev/null || echo "unknown")
  echo "📍 Current branch: $current_branch" >&2

  if [ "$current_branch" = "main" ]; then
    echo "⚠️  WARNING: On main branch! Create a worktree before making ANY changes:" >&2
    echo "   claude-tools worktree create <feature-name>" >&2
  fi
fi

echo "" >&2

exit 0
