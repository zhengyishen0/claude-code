#!/bin/bash
# PreToolUse hook: PDSD state machine
# Validates jj commit message format and state transitions
#
# Types: [task] [plan] [try] [reflect] [done] [adjust] [pivot] [drop]
#
# State machine:
#   [task]   → [plan]
#   [plan]   → [try]
#   [try]    → [try], [reflect]
#   [reflect] → [done], [adjust], [pivot], [drop]
#   [adjust] → [plan]
#   [pivot]  → [plan]
#
# Exit code 2 = block, exit 0 = allow

set -eo pipefail

input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name')

# Only handle Bash
if [[ "$tool_name" != "Bash" ]]; then
    exit 0
fi

command=$(echo "$input" | jq -r '.tool_input.command // ""')

# Only check jj new -m or jj describe -m
if [[ ! "$command" =~ jj[[:space:]]+(new|describe)[[:space:]].*-m ]]; then
    exit 0
fi

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
    echo "Valid types: [task] [plan] [try] [reflect] [done] [adjust] [pivot] [drop]" >&2
    echo "" >&2
    exit 2
fi

# Validate type
valid_types="task plan try reflect done adjust pivot drop"
if [[ ! " $valid_types " =~ " $new_type " ]]; then
    echo "" >&2
    echo "Error: Invalid type [$new_type]" >&2
    echo "Valid types: [task] [plan] [try] [reflect] [done] [adjust] [pivot] [drop]" >&2
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
    "task") [[ "$new_type" == "plan" ]] && valid_transition=true ;;
    "plan") [[ "$new_type" == "try" ]] && valid_transition=true ;;
    "try") [[ "$new_type" =~ ^(try|reflect)$ ]] && valid_transition=true ;;
    "reflect") [[ "$new_type" =~ ^(done|adjust|pivot|drop)$ ]] && valid_transition=true ;;
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
    echo "  [task]    → [plan]" >&2
    echo "  [plan]    → [try]" >&2
    echo "  [try]     → [try], [reflect]" >&2
    echo "  [reflect] → [done], [adjust], [pivot], [drop]" >&2
    echo "  [adjust]  → [plan]" >&2
    echo "  [pivot]   → [plan]" >&2
    echo "" >&2
    exit 2
fi

exit 0
