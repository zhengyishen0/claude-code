#!/bin/bash
# PreToolUse hook: Edit/Write guard
# Blocks Edit/Write unless in workspace with [task] and [plan]
#
# Exit code 2 = block, exit 0 = allow

set -eo pipefail

input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name')

# Only handle Edit/Write
if [[ "$tool_name" != "Edit" && "$tool_name" != "Write" ]]; then
    exit 0
fi

file_path=$(echo "$input" | jq -r '.tool_input.file_path // ""')
target_dir=$(dirname "$file_path")
[[ ! -d "$target_dir" ]] && target_dir="."

if jj root -R "$target_dir" &>/dev/null; then
    jj_root=$(jj root -R "$target_dir" 2>/dev/null || echo "")

    # Check if in workspace directory
    if [[ "$jj_root" == *"/.workspaces/"* ]]; then
        history=$(jj log -r 'ancestors(@)' --no-graph -T 'description ++ "\n"' -R "$target_dir" 2>/dev/null || echo "")

        # Check for [task]
        has_task=$(echo "$history" | grep -c '^\[task\]' || echo "0")
        if [[ "$has_task" -eq 0 ]]; then
            echo "" >&2
            echo "Error: Cannot $tool_name without [task] commit." >&2
            echo "" >&2
            echo "Create a task first:" >&2
            echo "  jj new main -m '[task] description (session-id)'" >&2
            echo "" >&2
            exit 2
        fi

        # Check for [plan]
        has_plan=$(echo "$history" | grep -c '^\[plan\]' || echo "0")
        if [[ "$has_plan" -eq 0 ]]; then
            echo "" >&2
            echo "Error: Cannot $tool_name without [plan] commit." >&2
            echo "" >&2
            echo "Create a plan first:" >&2
            echo "  jj new -m '[plan] hypothesis + approach (session-id)'" >&2
            echo "" >&2
            exit 2
        fi
    else
        # In main repo - block
        echo "" >&2
        echo "Error: Cannot $tool_name in default workspace." >&2
        echo "" >&2
        echo "Create a workspace first:" >&2
        echo "  jj workspace add --name <task>-<session-id> ../.workspaces/claude-code/<name>" >&2
        echo "  cd ../.workspaces/claude-code/<name>" >&2
        echo "  jj new main -m '[task] description (session-id)'" >&2
        echo "  jj new -m '[plan] hypothesis (session-id)'" >&2
        echo "" >&2
        exit 2
    fi

    # Block if on main bookmark
    current_bookmarks=$(jj log -r @ --no-graph -T 'bookmarks' -R "$target_dir" 2>/dev/null || echo "")
    if [[ "$current_bookmarks" == *"main"* ]]; then
        echo "" >&2
        echo "Error: Cannot $tool_name on main bookmark." >&2
        echo "" >&2
        exit 2
    fi
else
    # Git fallback
    target_branch=$(git -C "$target_dir" branch --show-current 2>/dev/null || git branch --show-current 2>/dev/null || echo "")
    if [[ "$target_branch" == "main" ]]; then
        echo "" >&2
        echo "Error: Cannot $tool_name on main branch." >&2
        echo "" >&2
        exit 2
    fi
fi

exit 0
