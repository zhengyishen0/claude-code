#!/bin/bash
# PreToolUse hook: Inject CLAUDE_SESSION_ID as environment variable
set -eo pipefail

# Read hook input
input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id')

# Export session ID as environment variable for this command execution
echo "CLAUDE_SESSION_ID=$session_id"

exit 0
