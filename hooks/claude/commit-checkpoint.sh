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
uncommitted_count=$(git -C "$active_worktree" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
if [ "$uncommitted_count" -gt 0 ]; then
    uncommitted_files=$(git -C "$active_worktree" status --porcelain 2>/dev/null | awk '{print $2}' | head -5)
    echo "" >&2
    echo "Warning: Uncommitted changes in \`$worktree_branch\` ($uncommitted_count files):" >&2
    echo "$uncommitted_files" | sed 's/^/  • /' >&2
    [ "$uncommitted_count" -gt 5 ] && echo "  • ... and $((uncommitted_count - 5)) more" >&2
    echo "" >&2
    echo "Consider: git add -A && git commit -m 'wip: <summary>'" >&2
    echo "If you're not working on $worktree_branch, kindly ignore this message." >&2
    echo "" >&2
    exit 2  # Block stop, force agent to respond
fi

exit 0
