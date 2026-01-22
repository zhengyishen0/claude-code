#!/bin/bash
# Stop hook: Prompt agent to commit or continue if uncommitted changes exist
# Soft prompt with block - forces agent to make a decision
#
# Exit code 2 = block stop (force agent to respond)
# Exit code 0 = allow stop

set -eo pipefail

input=$(cat)
stop_hook_active=$(echo "$input" | jq -r '.stop_hook_active // false')

# Avoid infinite loop - if already prompted, let it stop
if [ "$stop_hook_active" = "true" ]; then
    exit 0
fi

# Check for uncommitted changes (staged or unstaged)
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    echo "" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "⚠️  You have uncommitted changes." >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "" >&2
    echo "Please either:" >&2
    echo "  1. Continue working to complete the task" >&2
    echo "  2. Commit your progress with a meaningful message:" >&2
    echo "     git add -A && git commit -m 'checkpoint: <summary>'" >&2
    echo "" >&2
    echo "Report your progress before stopping." >&2
    echo "" >&2
    exit 2  # Block stop, force agent to respond
fi

exit 0
