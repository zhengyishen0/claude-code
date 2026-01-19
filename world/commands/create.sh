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
    create --task <id> <title> [--wait <condition>] [--need <criteria>]
    create --agent <status> <session-id> <content>

EVENT OPTIONS:
    --event <type>     Event type (git:commit, system, user, browser, file, api)
    --session <id>     Optional session ID

TASK OPTIONS (creates markdown file):
    --task <id>        Task ID (alphanumeric and dashes only)
    <title>            Task title/description
    --wait <cond>      Wait condition (default: "-" for immediate)
    --need <criteria>  Success criteria (default: "-")

AGENT OPTIONS (shorthand for --event):
    --agent <status>   start, active, finish, failed
    <session-id>       Session identifier
    <content>          Status description

EXAMPLES:
    create --event "git:commit" "fix: login bug"
    create --event "system" --session abc123 "task started"
    create --task "login-fix" "Fix user login bug" --need "tests pass"
    create --task "update-docs" "Update API documentation" --wait "after:login-fix"
    create --agent start abc123 "Starting task"
    create --agent finish abc123 "Task completed"

FORMAT:
    Event:  [timestamp] [event] <type> | <content>
    Task:   Creates tasks/<id>.md with frontmatter and structure
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
            echo "Error: --task requires <id> <title>"
            exit 1
        fi

        task_id="$1"
        title="$2"
        shift 2

        # Validate task_id format (alphanumeric and dashes only)
        if ! [[ "$task_id" =~ ^[a-zA-Z0-9-]+$ ]]; then
            echo "Error: Task ID must contain only alphanumeric characters and dashes"
            exit 1
        fi

        # Parse optional parameters
        wait="-"
        need="-"
        while [ $# -gt 0 ]; do
            case "$1" in
                --wait)
                    if [ $# -lt 2 ]; then
                        echo "Error: --wait requires a value"
                        exit 1
                    fi
                    wait="$2"
                    shift 2
                    ;;
                --need)
                    if [ $# -lt 2 ]; then
                        echo "Error: --need requires a value"
                        exit 1
                    fi
                    need="$2"
                    shift 2
                    ;;
                *)
                    echo "Error: Unknown option '$1'"
                    exit 1
                    ;;
            esac
        done

        # Generate session_id
        session_id=$(uuidgen | tr '[:upper:]' '[:lower:]')

        # Create tasks directory (at project root, not in world/)
        tasks_dir="$SCRIPT_DIR/../../tasks"
        mkdir -p "$tasks_dir"

        # Check if task already exists
        task_file="$tasks_dir/$task_id.md"
        if [ -f "$task_file" ]; then
            echo "Error: Task '$task_id' already exists at $task_file"
            exit 1
        fi

        # Create markdown file
        cat > "$task_file" <<EOF
---
id: $task_id
session_id: $session_id
title: $title
status: pending
wait: "$wait"
need: "$need"
created: $timestamp
---

# $title

## Wait Condition
$wait

## Execution Steps
1.

## Progress
- [ ]

EOF

        echo "✓ Created task: tasks/$task_id.md"
        echo "  Session ID: $session_id"
        echo "  Title: $title"
        echo "  Wait: $wait"
        echo "  Need: $need"
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
