#!/usr/bin/env bash
# claude-tools/world/commands/respond.sh
# Human-in-the-loop: Provide user response to a failed/waiting agent

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORLD_LOG="$SCRIPT_DIR/../world.log"
EVENT_CMD="$SCRIPT_DIR/event.sh"

show_help() {
    cat <<'EOF'
respond - Provide human response to an agent

USAGE:
    respond <session-id> <response>

DESCRIPTION:
    When an agent fails and needs human input (e.g., solve captcha),
    use this command to provide the response. The Level 2 supervisor
    will then retry the agent with your input.

EXAMPLES:
    respond abc123 "captcha solved: boats"
    respond def456 "I approved the request manually"
    respond ghi789 "skip this step, continue with default"

FLOW:
    1. Agent fails: [agent:failed][abc123] captcha required | need: solve captcha
    2. System escalates: [event:system][abc123] escalated to user
    3. User responds: respond abc123 "captcha solved"
    4. Level 2 sees user input, triggers retry
    5. Agent continues: [agent:retry][abc123] user provided: captcha solved
EOF
}

# Check arguments
if [ $# -lt 2 ]; then
    show_help
    exit 1
fi

if [ "${1:-}" = "help" ] || [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    show_help
    exit 0
fi

session_id="$1"
shift
response="$*"

# Verify session exists and is in failed state
if [ ! -f "$WORLD_LOG" ]; then
    echo "Error: world.log not found"
    exit 1
fi

# Get last status
last_entry=$(grep "\[agent:.*\]\[$session_id\]" "$WORLD_LOG" | tail -1 || echo "")

if [ -z "$last_entry" ]; then
    echo "Error: No agent found with session-id: $session_id"
    exit 1
fi

last_status=$(echo "$last_entry" | sed -E 's/.*\[agent:([^]]+)\].*/\1/')

if [ "$last_status" != "failed" ]; then
    echo "Warning: Agent $session_id is not in failed state (current: $last_status)"
    echo "Proceeding anyway..."
fi

# Log user response
"$EVENT_CMD" user "$session_id" "$response"

echo ""
echo "Response recorded for agent $session_id"
echo "Run 'supervisors/run.sh level2 process' to trigger retry"
