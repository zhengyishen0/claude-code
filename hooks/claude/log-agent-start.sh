#!/bin/bash
# Log agent start to world system
# Hook: SessionStart
# Requires: AGENT_SESSION_ID, AGENT_DESCRIPTION, CLAUDE_PROJECT_DIR
set -eo pipefail

# Need session ID and description to log
if [ -z "$AGENT_SESSION_ID" ] || [ -z "$AGENT_DESCRIPTION" ]; then
  exit 0
fi

# Use env var or fallback to cwd from input
input=$(cat)
cwd=$(echo "$input" | jq -r '.cwd // empty')
: "${CLAUDE_PROJECT_DIR:=$cwd}"

world_cmd="$CLAUDE_PROJECT_DIR/world/run.sh"
if [ -x "$world_cmd" ]; then
  "$world_cmd" create --agent start "$AGENT_SESSION_ID" "$AGENT_DESCRIPTION" 2>/dev/null || true
fi

exit 0
