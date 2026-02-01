#!/bin/bash
# PreToolUse hook: Block Edit/Write unless in a jj workspace
# Hard block - forces workspace usage for isolation
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
    # Get the jj root for the target directory
    jj_root=$(jj root -R "$target_dir" 2>/dev/null || echo "")

    # Check if target is in a workspace directory (not the main repo)
    # Workspaces are in .workspaces/ directory
    if [[ "$jj_root" == *"/.workspaces/"* ]]; then
        # Target is in a workspace directory - allow
        :
    else
        # Target is in main repo - check if in default workspace
        workspace_info=$(jj workspace list -R "$target_dir" 2>/dev/null || echo "")
        # In jj 0.37+, workspace list shows "name: change..." but doesn't mark current with @
        # If we're in the main repo root, we're in default workspace
        main_repo_root=$(jj root -R "$target_dir" 2>/dev/null || echo "")
        if [[ "$main_repo_root" == "$CLAUDE_PROJECT_DIR" ]] || [[ ! "$jj_root" == *"/.workspaces/"* ]]; then
            echo "" >&2
            echo "Warning: Cannot $tool_name in default workspace." >&2
            echo "" >&2
            echo "Create a workspace first:" >&2
            echo "  jj workspace add --name <task> ../.workspaces/claude-code/<task>" >&2
            echo "  cd ../.workspaces/claude-code/<task>" >&2
            echo "  jj new main -m '<task description>'" >&2
            echo "" >&2
            exit 2
        fi
    fi
    
    # Also block if @ has main bookmark (extra safety)
    current_bookmarks=$(jj log -r @ --no-graph -T 'bookmarks' -R "$target_dir" 2>/dev/null || echo "")
    if [[ "$current_bookmarks" == *"main"* ]]; then
        echo "" >&2
        echo "Warning: Cannot $tool_name on main bookmark." >&2
        echo "" >&2
        echo "Create a new change first: jj new main -m '<description>'" >&2
        echo "" >&2
        exit 2
    fi
else
    # git mode: fallback (keep for compatibility)
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
