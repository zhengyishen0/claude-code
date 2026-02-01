#!/bin/bash
# PreToolUse hook: PDSD enforcement
# 1. Block Edit/Write unless in workspace with [task]
# 2. Validate jj commit message format and state transitions
#
# Types: [task] [plan] [try] [learn] [done] [adjust] [pivot] [drop]
# Exit code 2 = block, exit 0 = allow

set -eo pipefail

input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name')

# =============================================================================
# Part 1: Edit/Write guard - must be in workspace with [task]
# =============================================================================
if [[ "$tool_name" == "Edit" || "$tool_name" == "Write" ]]; then
    file_path=$(echo "$input" | jq -r '.tool_input.file_path // ""')
    target_dir=$(dirname "$file_path")
    [[ ! -d "$target_dir" ]] && target_dir="."

    if jj root -R "$target_dir" &>/dev/null; then
        jj_root=$(jj root -R "$target_dir" 2>/dev/null || echo "")

        # Check if in workspace directory
        if [[ "$jj_root" == *"/.workspaces/"* ]]; then
            # In workspace - check for [task] commit
            has_task=$(jj log -r 'ancestors(@)' --no-graph -T 'description ++ "\n"' -R "$target_dir" 2>/dev/null | grep -c '^\[task\]' || echo "0")
            if [[ "$has_task" -eq 0 ]]; then
                echo "" >&2
                echo "Error: Cannot $tool_name without [task] commit." >&2
                echo "" >&2
                echo "Create a task first:" >&2
                echo "  jj new main -m '[task] description (session-id)'" >&2
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
            echo "" >&2
            exit 2
        fi

        # Block if on main bookmark
        current_bookmarks=$(jj log -r @ --no-graph -T 'bookmarks' -R "$target_dir" 2>/dev/null || echo "")
        if [[ "$current_bookmarks" == *"main"* ]]; then
            echo "" >&2
            echo "Error: Cannot $tool_name on main bookmark." >&2
            echo "" >&2
            echo "Create a new change: jj new main -m '[task] description'" >&2
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
fi

# =============================================================================
# Part 2: Bash guard - validate jj commit messages
# =============================================================================
if [[ "$tool_name" == "Bash" ]]; then
    command=$(echo "$input" | jq -r '.tool_input.command // ""')

    # Only check jj new -m or jj describe -m
    if [[ "$command" =~ jj[[:space:]]+(new|describe)[[:space:]].*-m ]]; then
        # Extract commit message
        if [[ "$command" =~ -m[[:space:]]+[\"\']([^\"\']+)[\"\'] ]]; then
            commit_msg="${BASH_REMATCH[1]}"
        elif [[ "$command" =~ -m[[:space:]]+([^[:space:]]+) ]]; then
            commit_msg="${BASH_REMATCH[1]}"
        else
            exit 0  # Can't parse, allow
        fi

        # Extract type
        if [[ "$commit_msg" =~ ^\[([a-z]+)\] ]]; then
            new_type="${BASH_REMATCH[1]}"
        else
            echo "" >&2
            echo "Error: Commit message must start with [type]" >&2
            echo "Valid types: [task] [plan] [try] [learn] [done] [adjust] [pivot] [drop]" >&2
            echo "" >&2
            exit 2
        fi

        # Validate type
        valid_types="task plan try learn done adjust pivot drop"
        if [[ ! " $valid_types " =~ " $new_type " ]]; then
            echo "" >&2
            echo "Error: Invalid type [$new_type]" >&2
            echo "Valid types: [task] [plan] [try] [learn] [done] [adjust] [pivot] [drop]" >&2
            echo "" >&2
            exit 2
        fi

        # Check [task] exists
        has_task=$(jj log -r 'ancestors(@)' --no-graph -T 'description ++ "\n"' 2>/dev/null | grep -c '^\[task\]' || echo "0")
        if [[ "$has_task" -eq 0 && "$new_type" != "task" ]]; then
            echo "" >&2
            echo "Error: First commit must be [task]" >&2
            echo "Create: jj new -m '[task] description (session-id)'" >&2
            echo "" >&2
            exit 2
        fi

        # Get last type
        last_type=$(jj log -r 'ancestors(@)' --no-graph -T 'description ++ "\n"' 2>/dev/null | \
            grep -E '^\[[a-z]+\]' | head -1 | grep -oE '^\[[a-z]+\]' | tr -d '[]' || echo "")

        # State machine validation
        valid_transition=false
        case "$last_type" in
            "") [[ "$new_type" == "task" ]] && valid_transition=true ;;
            "task") [[ "$new_type" =~ ^(plan|drop)$ ]] && valid_transition=true ;;
            "plan") [[ "$new_type" =~ ^(try|drop)$ ]] && valid_transition=true ;;
            "try") [[ "$new_type" =~ ^(try|learn|drop)$ ]] && valid_transition=true ;;
            "learn") [[ "$new_type" =~ ^(done|adjust|pivot|drop)$ ]] && valid_transition=true ;;
            "adjust"|"pivot") [[ "$new_type" == "plan" ]] && valid_transition=true ;;
            "done"|"drop")
                echo "" >&2
                echo "Error: [$last_type] is terminal. Merge to main or abandon workspace." >&2
                echo "" >&2
                exit 2
                ;;
        esac

        if [[ "$valid_transition" != "true" ]]; then
            echo "" >&2
            echo "Error: Invalid transition [$last_type] → [$new_type]" >&2
            echo "" >&2
            echo "Valid transitions:" >&2
            echo "  [task]   → [plan], [drop]" >&2
            echo "  [plan]   → [try], [drop]" >&2
            echo "  [try]    → [try], [learn], [drop]" >&2
            echo "  [learn]  → [done], [adjust], [pivot], [drop]" >&2
            echo "  [adjust] → [plan]" >&2
            echo "  [pivot]  → [plan]" >&2
            echo "" >&2
            exit 2
        fi
    fi
fi

exit 0
