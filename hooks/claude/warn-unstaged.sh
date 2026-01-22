#!/bin/bash
# PreToolUse hook: Warn if unstaged changes exist in current worktree
# Soft reminder - does not block, just warns
#
# Scoping: Only warns about the worktree being edited, not main or other worktrees
# Exit code 0 = allow (with optional warning to stderr)

set -eo pipefail

input=$(cat)

# Get target file path and its directory
file_path=$(echo "$input" | jq -r '.tool_input.file_path // ""')
target_dir=$(dirname "$file_path")

# Determine git directory for checks
if [[ -d "$target_dir" ]]; then
    git_dir="$target_dir"
else
    git_dir="."
fi

# Check if target is on main branch - skip warning if so
# (block-main-branch.sh will handle blocking, no need to warn)
target_branch=$(git -C "$git_dir" branch --show-current 2>/dev/null || echo "")
if [[ "$target_branch" == "main" ]]; then
    exit 0
fi

# Track the active worktree for commit-checkpoint.sh
# Get the git root directory (worktree path)
worktree_root=$(git -C "$git_dir" rev-parse --show-toplevel 2>/dev/null || echo "")
if [[ -n "$worktree_root" ]]; then
    echo "$worktree_root" > /tmp/claude-code-active-worktree
fi

# Get unstaged files (modified + untracked) for this worktree only
unstaged=$(git -C "$git_dir" status --porcelain 2>/dev/null | grep -E '^(\?\?| M|MM| D)' | awk '{print $2}' | head -5 || true)

if [[ -n "$unstaged" ]]; then
    count=$(git -C "$git_dir" status --porcelain 2>/dev/null | grep -cE '^(\?\?| M|MM| D)' || echo 0)
    echo "⚠️  Unstaged changes in $target_branch ($count files). Clean up before continuing:" >&2
    echo "$unstaged" | sed 's/^/   /' >&2
    [[ $count -gt 5 ]] && echo "   ... and $((count - 5)) more" >&2
    echo "" >&2
    echo "Consider: git add | git checkout | mv to tmp/ | rm (if not needed)" >&2
    echo "" >&2
fi

exit 0
