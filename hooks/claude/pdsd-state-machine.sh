#!/bin/bash
# PreToolUse hook: Enforce PDSD state machine for jj commits
# Validates: [task] → [plan] → [try] → [learn] → [done|retry|pivot|drop]
#
# Exit code 2 = block, exit 0 = allow

set -eo pipefail

input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name')

# Only check Bash commands
if [[ "$tool_name" != "Bash" ]]; then
    exit 0
fi

command=$(echo "$input" | jq -r '.tool_input.command // ""')

# Only check jj new -m or jj describe -m commands
if [[ ! "$command" =~ jj[[:space:]]+(new|describe)[[:space:]].*-m ]]; then
    exit 0
fi

# Extract the commit message from the command
# Handle both: jj new -m "msg" and jj new -m 'msg'
if [[ "$command" =~ -m[[:space:]]+[\"\']([^\"\']+)[\"\'] ]]; then
    commit_msg="${BASH_REMATCH[1]}"
elif [[ "$command" =~ -m[[:space:]]+([^[:space:]]+) ]]; then
    commit_msg="${BASH_REMATCH[1]}"
else
    # Can't parse message, allow (might be valid)
    exit 0
fi

# Extract type from commit message [type]
if [[ "$commit_msg" =~ ^\[([a-z]+)\] ]]; then
    new_type="${BASH_REMATCH[1]}"
else
    echo "" >&2
    echo "Error: Commit message must start with [type]" >&2
    echo "Valid types: [task] [plan] [try] [learn] [done] [retry] [pivot] [drop]" >&2
    echo "" >&2
    exit 2
fi

# Valid types
valid_types="task plan try learn done retry pivot drop"
if [[ ! " $valid_types " =~ " $new_type " ]]; then
    echo "" >&2
    echo "Error: Invalid type [$new_type]" >&2
    echo "Valid types: [task] [plan] [try] [learn] [done] [retry] [pivot] [drop]" >&2
    echo "" >&2
    exit 2
fi

# Check if [task] exists in this workspace's history
has_task=$(jj log -r 'ancestors(@)' --no-graph -T 'description ++ "\n"' 2>/dev/null | grep -c '^\[task\]' || echo "0")

if [[ "$has_task" -eq 0 && "$new_type" != "task" ]]; then
    echo "" >&2
    echo "Error: First commit must be [task]" >&2
    echo "Create a task first: jj new -m '[task] description (session-id)'" >&2
    echo "" >&2
    exit 2
fi

# Get last explicit type from history (skip empty descriptions)
last_type=$(jj log -r 'ancestors(@)' --no-graph -T 'description ++ "\n"' 2>/dev/null | \
    grep -E '^\[[a-z]+\]' | head -1 | grep -oE '^\[[a-z]+\]' | tr -d '[]' || echo "")

# If no previous type (first commit), only [task] allowed
if [[ -z "$last_type" && "$new_type" != "task" ]]; then
    echo "" >&2
    echo "Error: First commit must be [task]" >&2
    echo "" >&2
    exit 2
fi

# State machine transitions
# [task]  → [plan], [drop]
# [plan]  → [try], [drop]
# [try]   → [try], [learn], [drop]
# [learn] → [done], [retry], [pivot], [drop]
# [retry] → [plan]
# [pivot] → [plan]
# [done]  → (terminal - should merge to main)
# [drop]  → (terminal - abandon workspace)

valid_transition=false

case "$last_type" in
    "task")
        [[ "$new_type" =~ ^(plan|drop)$ ]] && valid_transition=true
        ;;
    "plan")
        [[ "$new_type" =~ ^(try|drop)$ ]] && valid_transition=true
        ;;
    "try")
        [[ "$new_type" =~ ^(try|learn|drop)$ ]] && valid_transition=true
        ;;
    "learn")
        [[ "$new_type" =~ ^(done|retry|pivot|drop)$ ]] && valid_transition=true
        ;;
    "retry"|"pivot")
        [[ "$new_type" == "plan" ]] && valid_transition=true
        ;;
    "done"|"drop")
        echo "" >&2
        echo "Error: [$last_type] is terminal. Merge to main or abandon workspace." >&2
        echo "" >&2
        exit 2
        ;;
    "")
        # No previous type, must be [task]
        [[ "$new_type" == "task" ]] && valid_transition=true
        ;;
esac

if [[ "$valid_transition" != "true" ]]; then
    echo "" >&2
    echo "Error: Invalid transition [$last_type] → [$new_type]" >&2
    echo "" >&2
    echo "Valid transitions:" >&2
    echo "  [task]  → [plan], [drop]" >&2
    echo "  [plan]  → [try], [drop]" >&2
    echo "  [try]   → [try], [learn], [drop]" >&2
    echo "  [learn] → [done], [retry], [pivot], [drop]" >&2
    echo "  [retry] → [plan]" >&2
    echo "  [pivot] → [plan]" >&2
    echo "" >&2
    exit 2
fi

exit 0
