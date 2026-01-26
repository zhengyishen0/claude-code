#!/bin/bash
# Inject task agent documentation into context
# Hook: SessionStart
# Requires: AGENT_TYPE=task, CLAUDE_PROJECT_DIR
set -eo pipefail

# Only for task agents
if [ "$AGENT_TYPE" != "task" ]; then
  exit 0
fi

# Use env var or fallback to cwd from input
input=$(cat)
cwd=$(echo "$input" | jq -r '.cwd // empty')
: "${CLAUDE_PROJECT_DIR:=$cwd}"

task_agent_doc="$CLAUDE_PROJECT_DIR/prompts/task_agent.md"
if [ -f "$task_agent_doc" ]; then
  echo "# Task Agent Context"
  cat "$task_agent_doc"
  echo ""
fi

exit 0
