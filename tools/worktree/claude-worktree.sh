#!/bin/bash

# Create temp worktree
TIMESTAMP=$(date +%s)
TEMP_NAME="temp-$TIMESTAMP"
WORKTREE_PATH="../claude-code-$TEMP_NAME"

echo "Creating temp worktree..."
git worktree add -b "$TEMP_NAME" "$WORKTREE_PATH"

if [ $? -ne 0 ]; then
    echo "Failed to create temp worktree"
    exit 1
fi

ABS_PATH="$(cd "$WORKTREE_PATH" && pwd)"
echo "Created temp worktree: $ABS_PATH"
echo "Starting Claude session..."

# Change to worktree and start Claude
cd "$ABS_PATH"
claude

# Cleanup on exit: if still temp, remove it
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null)
if [[ "$CURRENT_BRANCH" == temp-* ]]; then
    echo ""
    echo "Cleaning up temp worktree (no changes kept)..."
    cd ..
    git worktree remove "$ABS_PATH" 2>/dev/null
    git branch -D "$CURRENT_BRANCH" 2>/dev/null
    echo "Temp worktree removed"
else
    echo ""
    echo "Worktree kept (renamed to: $CURRENT_BRANCH)"
fi
