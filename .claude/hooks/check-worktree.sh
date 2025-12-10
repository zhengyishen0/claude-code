#!/bin/bash

# Get current branch
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null)

if [ $? -ne 0 ]; then
  echo "Not a git repository"
  exit 0
fi

# Check if on main branch
if [ "$CURRENT_BRANCH" = "main" ]; then
  cat <<EOF
⚠️  Currently on main branch

For code changes, consider creating a worktree:
  claude-tools worktree create feature-name

This will create the worktree and launch a new Claude session automatically.

Skip for trivial changes (docs, typos).
EOF
fi

echo "Current branch: $CURRENT_BRANCH"
exit 0
