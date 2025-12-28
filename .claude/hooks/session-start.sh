#!/bin/bash
# SessionStart hook: Export current session ID and show git branch info
# This makes the session ID available as $CLAUDE_CODE_SESSION_ID throughout the session
set -eo pipefail

# Read hook input with session_id and cwd
input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id')
cwd=$(echo "$input" | jq -r '.cwd')

# Export to CLAUDE_ENV_FILE so it's available to all bash commands in this session
if [ -n "$CLAUDE_ENV_FILE" ] && [ -n "$session_id" ]; then
  echo "export CLAUDE_CODE_SESSION_ID='$session_id'" >> "$CLAUDE_ENV_FILE"
fi

# Show current git branch and worktree reminder
if [ -d "$cwd/.git" ] || git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
  current_branch=$(git -C "$cwd" branch --show-current 2>/dev/null || echo "unknown")
  echo "" >&2
  echo "📍 Current branch: $current_branch" >&2

  if [ "$current_branch" = "main" ]; then
    echo "⚠️  WARNING: On main branch! Create a worktree before making ANY changes:" >&2
    echo "   claude-tools worktree create <feature-name>" >&2
  fi
  echo "" >&2
fi

exit 0
