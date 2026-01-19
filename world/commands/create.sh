#!/usr/bin/env bash
# world/commands/create.sh
# Unified create command for events and tasks

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORLD_LOG="$SCRIPT_DIR/../world.log"

show_help() {
    cat <<'EOF'
create - Write event or task to world.log

USAGE:
    create --event <type> [--session <id>] <content>
    create --task <id> <status> [<trigger>] [<description>] [--need <criteria>]
    create --agent <status> <session-id> <content>

EVENT OPTIONS:
    --event <type>     Event type (git:commit, system, user, browser, file, api)
    --session <id>     Optional session ID

TASK OPTIONS:
    --task <id>        Task ID
    <status>           pending, running, done, failed
    <trigger>          now, <datetime>, after:<task-id> (only for pending)
    <description>      Task description (only for pending)
    --need <criteria>  Success criteria (only for pending)

AGENT OPTIONS (shorthand for --event):
    --agent <status>   start, active, finish, failed
    <session-id>       Session identifier
    <content>          Status description

EXAMPLES:
    create --event "git:commit" "fix: login bug"
    create --event "system" --session abc123 "task started"
    create --task "login-fix" "pending" "now" "Fix login" --need "tests pass"
    create --task "login-fix" "running"
    create --task "login-fix" "done"
    create --agent start abc123 "Starting task"
    create --agent finish abc123 "Task completed"

FORMAT:
    Event:  [timestamp] [event] <type> | <content>
    Task:   [timestamp] [task] <id> | <status> | <trigger> | <description> | need: <criteria>
EOF
}

# Ensure log exists
touch "$WORLD_LOG"

# Generate timestamp (ISO 8601 UTC)
timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Parse arguments
if [ $# -lt 1 ]; then
    show_help
    exit 1
fi

case "$1" in
    --event)
        shift
        if [ $# -lt 1 ]; then
            echo "Error: --event requires <type> and <content>"
            exit 1
        fi

        event_type="$1"
        shift

        # Check for --session
        session_id=""
        if [ "${1:-}" = "--session" ]; then
            shift
            session_id="$1"
            shift
        fi

        if [ $# -lt 1 ]; then
            echo "Error: --event requires <content>"
            exit 1
        fi

        content="$*"

        # Build entry
        if [ -n "$session_id" ]; then
            entry="[$timestamp] [event] $event_type:$session_id | $content"
        else
            entry="[$timestamp] [event] $event_type | $content"
        fi

        echo "$entry" >> "$WORLD_LOG"
        echo "$entry"
        ;;

    --task)
        shift
        if [ $# -lt 2 ]; then
            echo "Error: --task requires <id> <status>"
            exit 1
        fi

        task_id="$1"
        status="$2"
        shift 2

        # Validate status
        case "$status" in
            pending|running|done|failed) ;;
            *)
                echo "Error: Invalid status '$status'. Must be: pending, running, done, failed"
                exit 1
                ;;
        esac

        # For pending, we need trigger and description
        if [ "$status" = "pending" ]; then
            if [ $# -lt 2 ]; then
                echo "Error: pending task requires <trigger> <description>"
                exit 1
            fi

            trigger="$1"
            shift

            # Parse remaining args for description and --need
            description=""
            need=""
            while [ $# -gt 0 ]; do
                if [ "$1" = "--need" ]; then
                    shift
                    need="$1"
                    shift
                else
                    if [ -n "$description" ]; then
                        description="$description $1"
                    else
                        description="$1"
                    fi
                    shift
                fi
            done

            if [ -z "$description" ]; then
                echo "Error: pending task requires <description>"
                exit 1
            fi

            if [ -n "$need" ]; then
                entry="[$timestamp] [task] $task_id | $status | $trigger | $description | need: $need"
            else
                entry="[$timestamp] [task] $task_id | $status | $trigger | $description"
            fi
        else
            # For running/done/failed, just update status
            entry="[$timestamp] [task] $task_id | $status"
        fi

        echo "$entry" >> "$WORLD_LOG"
        echo "$entry"
        ;;

    --agent)
        shift
        if [ $# -lt 3 ]; then
            echo "Error: --agent requires <status> <session-id> <content>"
            exit 1
        fi

        agent_status="$1"
        session_id="$2"
        shift 2
        content="$*"

        # Validate status
        case "$agent_status" in
            start|active|finish|failed) ;;
            *)
                echo "Error: Invalid agent status '$agent_status'. Must be: start, active, finish, failed"
                exit 1
                ;;
        esac

        # Agent is just a typed event
        entry="[$timestamp] [event] agent:$agent_status:$session_id | $content"

        echo "$entry" >> "$WORLD_LOG"
        echo "$entry"
        ;;

    help|-h|--help)
        show_help
        ;;

    *)
        echo "Error: Unknown option '$1'"
        echo "Run 'world create --help' for usage"
        exit 1
        ;;
esac
