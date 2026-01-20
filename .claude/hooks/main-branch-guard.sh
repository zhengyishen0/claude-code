#!/bin/bash
# PreToolUse hook for Edit/Write:
# 1. Warn if unstaged changes exist (keep tree clean)
# 2. Block if target is on main branch
#
# Exit code 2 = block, exit 1 = warn only

set -eo pipefail

input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name')

# Only check Edit and Write
if [[ "$tool_name" != "Edit" && "$tool_name" != "Write" ]]; then
    exit 0
fi

# Get target file path and its directory
file_path=$(echo "$input" | jq -r '.tool_input.file_path // ""')
target_dir=$(dirname "$file_path")

# Determine git directory for checks
if [[ -d "$target_dir" ]]; then
    git_dir="$target_dir"
else
    git_dir="."
fi

# --- Check 1: Warn if unstaged changes exist ---
# Get unstaged files (modified + untracked)
unstaged=$(git -C "$git_dir" status --porcelain 2>/dev/null | grep -E '^(\?\?| M|MM| D)' | awk '{print $2}' | head -5)
if [[ -n "$unstaged" ]]; then
    count=$(git -C "$git_dir" status --porcelain 2>/dev/null | grep -cE '^(\?\?| M|MM| D)' || echo 0)
    echo "⚠️  Unstaged changes ($count files). Clean up before continuing:" >&2
    echo "$unstaged" | sed 's/^/   /' >&2
    [[ $count -gt 5 ]] && echo "   ... and $((count - 5)) more" >&2
    echo "" >&2
    echo "Consider: git add | git checkout | mv to tmp/ | rm (if not needed)" >&2
    echo "" >&2
fi

# --- Check 2: Block if on main branch ---

# Check branch at target directory (handles worktrees correctly)
if [[ -d "$target_dir" ]]; then
    target_branch=$(git -C "$target_dir" branch --show-current 2>/dev/null || echo "")
else
    # Directory doesn't exist yet, fall back to cwd
    target_branch=$(git branch --show-current 2>/dev/null || echo "")
fi

# Block if target is on main
if [[ "$target_branch" == "main" ]]; then
    echo "BLOCKED: Cannot $tool_name on main branch." >&2
    echo "" >&2
    echo "Create a worktree first:" >&2
    echo "  worktree create <feature-name>" >&2
    exit 2
fi

exit 0
