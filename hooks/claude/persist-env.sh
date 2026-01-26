#!/bin/bash
# Persist session environment variables for subsequent Bash commands
# Hook: SessionStart
set -eo pipefail

input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id // empty')
cwd=$(echo "$input" | jq -r '.cwd // empty')

# Persist to CLAUDE_ENV_FILE (available for all subsequent Bash commands)
if [ -n "$CLAUDE_ENV_FILE" ]; then
  [ -n "$session_id" ] && echo "export CLAUDE_SESSION_ID=\"$session_id\"" >> "$CLAUDE_ENV_FILE"
  [ -n "$cwd" ] && echo "export CLAUDE_CWD=\"$cwd\"" >> "$CLAUDE_ENV_FILE"
fi

# Output to context (Claude sees this)
if [ -n "$session_id" ]; then
  echo "Session: $session_id"
fi

exit 0
