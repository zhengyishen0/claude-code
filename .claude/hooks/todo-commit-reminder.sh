#!/bin/bash
# PreToolUse hook for TodoWrite:
# Remind to commit when all todos are completed

set -eo pipefail

# Source paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../paths.sh"

input=$(cat)
todos=$(echo "$input" | jq -r '.tool_input.todos // []')

total=$(echo "$todos" | jq 'length')
completed=$(echo "$todos" | jq '[.[] | select(.status == "completed")] | length')

# Only remind if there are todos and all are completed
if [ "$total" -gt 0 ] && [ "$total" -eq "$completed" ]; then
    echo ""
    echo "✅ All todos completed. Consider: git add && git commit"
    echo ""
fi

exit 0
