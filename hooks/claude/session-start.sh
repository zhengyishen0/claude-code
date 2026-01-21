#!/bin/bash
# SessionStart hook: Agent-type specific context + World logging
set -eo pipefail

# Read hook input
input=$(cat)
cwd=$(echo "$input" | jq -r '.cwd')

# Use env vars (set by spawn.sh) or fallback to cwd-based paths
: "${CLAUDE_PROJECT_DIR:=$cwd}"

# 1. Provide agent-specific documentation based on AGENT_TYPE
if [ "$AGENT_TYPE" = "task" ]; then
  task_agent_doc="$CLAUDE_PROJECT_DIR/prompts/task_agent.md"
  if [ -f "$task_agent_doc" ]; then
    echo "# Task Agent Context"
    cat "$task_agent_doc"
    echo ""
  fi
fi

# 2. Log agent start to world (if session ID and description provided)
if [ -n "$AGENT_SESSION_ID" ] && [ -n "$AGENT_DESCRIPTION" ]; then
  world_cmd="$CLAUDE_PROJECT_DIR/world/run.sh"
  if [ -x "$world_cmd" ]; then
    "$world_cmd" create --agent start "$AGENT_SESSION_ID" "$AGENT_DESCRIPTION" 2>/dev/null || true
  fi
fi

exit 0
