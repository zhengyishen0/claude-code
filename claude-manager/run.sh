#!/usr/bin/env bash
# claude-manager/run.sh
# Manager service for processing environment events

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_TOOL="$PROJECT_ROOT/claude-tools/environment/run.sh"
SYSTEM_PROMPT="$SCRIPT_DIR/system-prompt.md"

SLEEP_ACTIVE=300    # 5 minutes
SLEEP_IDLE=1800     # 30 minutes

#──────────────────────────────────────────────────────────────
# Status Check
#──────────────────────────────────────────────────────────────

check_status() {
    # Find last manager lifecycle event
    local last_event=$("$ENV_TOOL" check 2>/dev/null | grep '^\[.*\] \[system\] \[.*:' | tail -1 || echo "")

    # Read entire log if check returns nothing
    if [ -z "$last_event" ]; then
        local env_log="$PROJECT_ROOT/claude-tools/environment/environment.log"
        if [ -f "$env_log" ]; then
            last_event=$(grep '^\[.*\] \[system\] \[.*:' "$env_log" | tail -1 || echo "")
        fi
    fi

    if [ -z "$last_event" ]; then
        STATUS="STOPPED"
        MANAGER_PID=""
        MANAGER_SESSION_ID=""
        return
    fi

    # Extract PID-SessionID and status
    # Format: [timestamp] [system] [12345-a7f3c1:started] description
    local id_status=$(echo "$last_event" | sed -E 's/.*\[([0-9]+-[a-z0-9]+):(started|stopped)\].*/\1:\2/')

    if [[ ! "$id_status" =~ ^[0-9]+-[a-z0-9]+:(started|stopped)$ ]]; then
        STATUS="STOPPED"
        MANAGER_PID=""
        MANAGER_SESSION_ID=""
        return
    fi

    local full_id="${id_status%:*}"
    local event_status="${id_status#*:}"

    MANAGER_PID="${full_id%-*}"
    MANAGER_SESSION_ID="${full_id#*-}"

    if [ "$event_status" = "stopped" ]; then
        STATUS="STOPPED"
        return
    fi

    # Check if process still alive
    if ps -p "$MANAGER_PID" > /dev/null 2>&1; then
        STATUS="RUNNING"
    else
        STATUS="STOPPED"
    fi
}

#──────────────────────────────────────────────────────────────
# Commands
#──────────────────────────────────────────────────────────────

cmd_start() {
    check_status

    if [ "$STATUS" = "RUNNING" ]; then
        echo "Manager already running"
        echo "  PID: $MANAGER_PID"
        echo "  Session: $MANAGER_SESSION_ID"
        exit 0
    fi

    echo "Starting manager..."

    # Generate session ID
    local session_id=$(uuidgen | tr '[:upper:]' '[:lower:]' | cut -c1-8)

    # Start background loop
    (
        local was_recently_active=true

        # Log start
        "$ENV_TOOL" event [system] [$$-$session_id:started] "manager started"

        while true; do
            # Check for new events
            local new_entries=$("$ENV_TOOL" check)

            if [ -n "$new_entries" ]; then
                # Has new entries - process with Claude
                was_recently_active=true

                claude -p "New environment events:

$new_entries

Process these events and take appropriate action.

Available tools (use Bash tool to call):
- $ENV_TOOL event [source] [description]
- $ENV_TOOL event [source] [task-id:status] description

Examples:
  # Create new task
  $ENV_TOOL event [agent] [task-002:ready] \"research domains for task-001\"

  # Update task status
  $ENV_TOOL event [agent] [task-001:done] \"completed successfully\"

  # Add note
  $ENV_TOOL event [agent] \"observation or decision\"

Decision framework:
- [task-X:active] → Break into 3-5 smaller tasks
- [task-X:ready] → Check if ready to execute (check dependencies, capacity)
- [task-X:blocked] → Analyze blocker, try to unblock
- [task-X:done] → Check if unblocks other tasks
- Other events → Assess if action needed

Always explain your reasoning briefly, then take action.
" --model opus --system-prompt "$(cat "$SYSTEM_PROMPT" 2>/dev/null || echo 'You are the manager agent. Process environment events and coordinate work.')"

                # Continue immediately (check again)
                continue

            else
                # No new entries - sleep
                if [ "$was_recently_active" = true ]; then
                    # First idle - short sleep
                    sleep $SLEEP_ACTIVE
                    was_recently_active=false
                else
                    # Still idle - long sleep
                    sleep $SLEEP_IDLE
                fi
            fi
        done
    ) &

    local manager_pid=$!

    echo "Manager started"
    echo "  PID: $manager_pid"
    echo "  Session: $session_id"
}

cmd_stop() {
    check_status

    if [ "$STATUS" = "STOPPED" ]; then
        echo "Manager not running"
        exit 0
    fi

    echo "Stopping manager (PID: $MANAGER_PID, Session: $MANAGER_SESSION_ID)..."

    kill "$MANAGER_PID" 2>/dev/null || true

    # Log stop
    "$ENV_TOOL" event [system] [$MANAGER_PID-$MANAGER_SESSION_ID:stopped] "manager stopped"

    echo "Manager stopped"
}

cmd_status() {
    check_status

    if [ "$STATUS" = "RUNNING" ]; then
        echo "Manager running"
        echo "  PID: $MANAGER_PID"
        echo "  Session: $MANAGER_SESSION_ID"
    else
        echo "Manager not running"
    fi
}

cmd_help() {
    cat <<EOF
claude-manager - Event processing service

USAGE:
    claude-manager/run.sh <command>

COMMANDS:
    start       Start manager daemon
    stop        Stop manager daemon
    status      Check manager status

EXAMPLES:
    # Start manager
    claude-manager/run.sh start

    # Check if running
    claude-manager/run.sh status

    # Stop manager
    claude-manager/run.sh stop

The manager continuously processes events from the environment log.
EOF
}

#──────────────────────────────────────────────────────────────
# Router
#──────────────────────────────────────────────────────────────

case "${1:-help}" in
    start)
        cmd_start
        ;;
    stop)
        cmd_stop
        ;;
    status)
        cmd_status
        ;;
    help|-h|--help)
        cmd_help
        ;;
    *)
        echo "Unknown command: $1"
        echo "Run 'claude-manager/run.sh help' for usage"
        exit 1
        ;;
esac
