#!/bin/bash
# Stop hook: Prompt agent to commit or continue if uncommitted changes exist
# Soft prompt with block - forces agent to make a decision
#
# Scoping: Only checks the worktree the agent was working on, not main or other worktrees
# Exit code 2 = block stop (force agent to respond)
# Exit code 0 = allow stop

set -eo pipefail

input=$(cat)
stop_hook_active=$(echo "$input" | jq -r '.stop_hook_active // false')

# Avoid infinite loop - if already prompted, let it stop
if [ "$stop_hook_active" = "true" ]; then
    exit 0
fi

# Read the active worktree (set by warn-unstaged.sh during Edit/Write)
active_worktree=""
if [ -f /tmp/claude-code-active-worktree ]; then
    active_worktree=$(cat /tmp/claude-code-active-worktree)
fi

# If no worktree was tracked, agent didn't edit any files (or only tried main)
# Allow stop without warning
if [ -z "$active_worktree" ] || [ ! -d "$active_worktree" ]; then
    exit 0
fi

# Check if active worktree is on main - skip warning if so
# (agent can't edit main anyway, changes would be human's)
worktree_branch=$(git -C "$active_worktree" branch --show-current 2>/dev/null || echo "")
if [ "$worktree_branch" = "main" ]; then
    exit 0
fi

# Check for uncommitted changes in the active worktree only
if [ -n "$(git -C "$active_worktree" status --porcelain 2>/dev/null)" ]; then
    echo "" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "⚠️  You have uncommitted changes in $worktree_branch." >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "" >&2
    echo "Please either:" >&2
    echo "  1. Continue working to complete the task" >&2
    echo "  2. Commit your progress with a meaningful message:" >&2
    echo "     git -C $active_worktree add -A && git -C $active_worktree commit -m 'checkpoint: <summary>'" >&2
    echo "" >&2
    echo "Report your progress before stopping." >&2
    echo "" >&2
    exit 2  # Block stop, force agent to respond
fi

exit 0
