#!/bin/bash
# SessionStart hook: Export current session ID to CLAUDE_ENV_FILE
# This makes the session ID available as $CLAUDE_CODE_SESSION_ID throughout the session
set -eo pipefail

# Read hook input with session_id
input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id')

# Export to CLAUDE_ENV_FILE so it's available to all bash commands in this session
if [ -n "$CLAUDE_ENV_FILE" ] && [ -n "$session_id" ]; then
  echo "export CLAUDE_CODE_SESSION_ID='$session_id'" >> "$CLAUDE_ENV_FILE"
fi

exit 0
