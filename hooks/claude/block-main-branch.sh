#!/bin/bash
# PreToolUse hook: Block Edit/Write on main branch
# Hard block - forces worktree usage
#
# Exit code 2 = block, exit 0 = allow

set -eo pipefail

input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name')

# Get target file path and its directory
file_path=$(echo "$input" | jq -r '.tool_input.file_path // ""')
target_dir=$(dirname "$file_path")

# Check branch at target directory (handles worktrees correctly)
if [[ -d "$target_dir" ]]; then
    target_branch=$(git -C "$target_dir" branch --show-current 2>/dev/null || echo "")
else
    # Directory doesn't exist yet, fall back to cwd
    target_branch=$(git branch --show-current 2>/dev/null || echo "")
fi

# Block if target is on main
if [[ "$target_branch" == "main" ]]; then
    echo "" >&2
    echo "Warning: Cannot $tool_name on main branch." >&2
    echo "" >&2
    echo "Create a worktree first: worktree create <feature-name>" >&2
    echo "If you're not working on main, kindly ignore this message." >&2
    echo "" >&2
    exit 2
fi

exit 0
