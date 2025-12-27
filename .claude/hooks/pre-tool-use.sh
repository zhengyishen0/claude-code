#!/bin/bash
# PreToolUse hook to track current session ID for memory tools

# Read hook input with session_id
read -r input
session_id=$(echo "$input" | jq -r '.session_id')

# Write session ID to file keyed by SSE port (unique per session)
if [ -n "$CLAUDE_CODE_SSE_PORT" ] && [ -n "$session_id" ]; then
  mkdir -p ~/.claude/session-ports
  echo "$session_id" > ~/.claude/session-ports/$CLAUDE_CODE_SSE_PORT.txt
fi

exit 0
