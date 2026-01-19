#!/bin/bash
# SessionStart hook: Agent-type specific context + Git branch warning + World logging
set -eo pipefail

# Read hook input
input=$(cat)
cwd=$(echo "$input" | jq -r '.cwd')

# 1. Provide agent-specific documentation based on AGENT_TYPE
if [ "$AGENT_TYPE" = "task" ]; then
  task_agent_doc="$CLAUDE_PROJECT_DIR/TASK_AGENT.md"
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

# 3. Check git branch and warn if on main
if [ -d "$cwd/.git" ] || git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
  current_branch=$(git -C "$cwd" branch --show-current 2>/dev/null || echo "unknown")

  if [ "$current_branch" = "main" ]; then
    echo ""
    echo "📍 Current branch: $current_branch"
    echo "⚠️  WARNING: On main branch! Create a worktree before making ANY changes:"
    echo "   claude-tools worktree create <feature-name>"
    echo ""
  fi
fi

exit 0
