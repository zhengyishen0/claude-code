#!/bin/bash
# Block Edit/Write operations on main branch
# Exit code 2 = block tool execution (exit 1 only shows warning)

set -eo pipefail

input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name')

# Get current branch
current_branch=$(git branch --show-current 2>/dev/null || echo "")

# Only guard when on main branch
if [[ "$current_branch" != "main" ]]; then
    exit 0
fi

# Block Edit and Write on main
if [[ "$tool_name" == "Edit" || "$tool_name" == "Write" ]]; then
    echo "BLOCKED: Cannot $tool_name on main branch." >&2
    echo "" >&2
    echo "Create a worktree first:" >&2
    echo "  worktree create <feature-name>" >&2
    exit 2
fi

# For Bash, check if it's a direct commit (not merge)
if [[ "$tool_name" == "Bash" ]]; then
    command=$(echo "$input" | jq -r '.tool_input.command // ""')

    # Block: git commit, git add + commit
    if echo "$command" | grep -qE 'git\s+(commit|add)'; then
        # Allow if it's a merge commit
        if echo "$command" | grep -qE 'git\s+merge'; then
            exit 0
        fi
        echo "BLOCKED: Cannot commit on main branch." >&2
        echo "" >&2
        echo "Create a worktree first, or use 'git merge' to merge a feature branch." >&2
        exit 2
    fi
fi

exit 0
