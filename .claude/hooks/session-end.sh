#!/bin/bash
# SessionEnd hook: Report agent completion to world.log
set -eo pipefail

# Read hook input
input=$(cat)
cwd=$(echo "$input" | jq -r '.cwd')
exit_code=$(echo "$input" | jq -r '.exit_code')

# Only process if we have agent environment variables
if [ -z "$AGENT_SESSION_ID" ]; then
  exit 0
fi

cd "$cwd" || exit 0

# Ensure world tool exists
WORLD_CMD="${CLAUDE_PROJECT_DIR:-$(pwd)}/world/run.sh"
if [ ! -f "$WORLD_CMD" ]; then
  exit 0
fi

# 1. Record agent end for all agents
"$WORLD_CMD" create --event "agent:end" "$AGENT_SESSION_ID" "session finished (exit code: $exit_code)" 2>/dev/null || true

# 2. For Task Agents with REPORT.md, record completion
if [ "$AGENT_TYPE" = "task" ] && [ -f "REPORT.md" ]; then
  summary=$(head -5 "REPORT.md" | tr '\n' ' ')
  "$WORLD_CMD" create --event "agent:finish" "$AGENT_SESSION_ID" "$summary" 2>/dev/null || true
fi

exit 0
