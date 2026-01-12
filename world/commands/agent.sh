#!/usr/bin/env bash
# claude-tools/world/commands/agent.sh
# Log agent status to world.log

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORLD_LOG="$SCRIPT_DIR/../world.log"

show_help() {
    cat <<'EOF'
agent - Log agent status to world.log

USAGE:
    agent <status> <session-id> <output>

ARGUMENTS:
    status      Agent status: start, active, finish, verified, retry, failed
    session-id  Claude Code session identifier
    output      Description (for start/failed, include "| need: criteria")

STATUSES:
    start       Project created, includes success criteria
    active      Agent is working
    finish      Agent believes task is complete
    verified    Supervisor confirmed success
    retry       Supervisor says try again
    failed      Cannot proceed, needs escalation

EXAMPLES:
    agent start abc123 "Book Tokyo flights | need: confirmation number"
    agent active abc123 "searching flights on google.com/flights"
    agent finish abc123 "Booked JAL $450, confirmation #XYZ789"
    agent verified abc123 "success criteria met"
    agent retry abc123 "confirmation not found, check booking page"
    agent failed abc123 "captcha required | need: solve captcha"

FORMAT:
    [timestamp][agent:status][session-id] output | need: criteria
EOF
}

# Check arguments
if [ $# -lt 3 ]; then
    show_help
    exit 1
fi

status="$1"
session_id="$2"
shift 2
output="$*"

# Validate status
valid_statuses="start active finish verified retry failed"
if ! echo "$valid_statuses" | grep -qw "$status"; then
    echo "Invalid status: $status"
    echo "Valid statuses: $valid_statuses"
    exit 1
fi

# Warn if start/failed without "| need:"
if [[ "$status" == "start" || "$status" == "failed" ]] && [[ ! "$output" =~ \|[[:space:]]*need: ]]; then
    echo "Warning: $status should include '| need: criteria'" >&2
fi

# Ensure log exists
touch "$WORLD_LOG"

# Generate timestamp (ISO 8601 UTC)
timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Write entry
entry="[$timestamp][agent:$status][$session_id] $output"
echo "$entry" >> "$WORLD_LOG"

# Echo back for confirmation
echo "$entry"
