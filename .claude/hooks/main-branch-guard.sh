#!/bin/bash
# Block Edit/Write operations on main branch
# Exit code 2 = block tool execution (exit 1 only shows warning)

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
