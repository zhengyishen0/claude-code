#!/bin/bash
# Stop hook: Check for undescribed jj changes
# Simplified for jj - no "uncommitted" concept
#
# Exit code 2 = block stop, exit 0 = allow

set -eo pipefail

input=$(cat)
stop_hook_active=$(echo "$input" | jq -r '.stop_hook_active // false')

# Avoid infinite loop
if [ "$stop_hook_active" = "true" ]; then
    exit 0
fi

# Skip if not using jj
if ! jj root &>/dev/null; then
    exit 0
fi

# Check if @ has no description
description=$(jj log -r @ --no-graph -T 'description' 2>/dev/null || echo "")
if [[ -z "$description" || "$description" == "(no description set)" ]]; then
    echo "" >&2
    echo "Note: Working copy has no description." >&2
    echo "Consider: jj describe -m '<summary>'" >&2
    echo "" >&2
    # Soft warning, don't block
    exit 0
fi

exit 0
