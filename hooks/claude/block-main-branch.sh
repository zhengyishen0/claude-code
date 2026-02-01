#!/bin/bash
# PreToolUse hook: Block Edit/Write on main
# Hard block - forces jj new or workspace usage
#
# Exit code 2 = block, exit 0 = allow

set -eo pipefail

input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name')

# Get target file path and its directory
file_path=$(echo "$input" | jq -r '.tool_input.file_path // ""')
target_dir=$(dirname "$file_path")
[[ ! -d "$target_dir" ]] && target_dir="."

# Check if using jj
if jj root -R "$target_dir" &>/dev/null; then
    # jj mode: check if @ has main bookmark
    current_bookmarks=$(jj log -r @ --no-graph -T 'bookmarks' -R "$target_dir" 2>/dev/null || echo "")
    if [[ "$current_bookmarks" == *"main"* ]]; then
        echo "" >&2
        echo "Warning: Cannot $tool_name on main." >&2
        echo "" >&2
        echo "Create a new change first: jj new main" >&2
        echo "Or use workspace: jj workspace add --name <feature> <path>" >&2
        echo "" >&2
        exit 2
    fi
else
    # git mode: fallback
    if [[ -d "$target_dir" ]]; then
        target_branch=$(git -C "$target_dir" branch --show-current 2>/dev/null || echo "")
    else
        target_branch=$(git branch --show-current 2>/dev/null || echo "")
    fi
    if [[ "$target_branch" == "main" ]]; then
        echo "" >&2
        echo "Warning: Cannot $tool_name on main branch." >&2
        echo "" >&2
        echo "Create a worktree first: worktree create <feature-name>" >&2
        echo "" >&2
        exit 2
    fi
fi

exit 0
