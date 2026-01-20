#!/usr/bin/env bash
# world/commands/create.sh
# Unified create command for events, tasks, and agents

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORLD_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORLD_LOG="$WORLD_DIR/world.log"
TASKS_DIR="$WORLD_DIR/tasks"

show_help() {
    cat <<'EOF'
create - Create events, tasks, or agents

USAGE:
    create --event <type> [--session <id>] <content>
    create --task <id> <title> [--wait <cond>] [--need <criteria>]
    create --agent task <title> [--wait <cond>] [--need <criteria>]
    create --agent supervisor

EVENT OPTIONS:
    --event <type>     Event type (git:commit, system, user, etc.)
    --session <id>     Optional session ID

TASK OPTIONS (creates markdown with specified ID):
    --task <id>        Task ID (alphanumeric and dashes only)
    <title>            Task title/description
    --wait <cond>      Wait condition (default: "-")
    --need <criteria>  Success criteria (default: "-")

AGENT OPTIONS (auto-generate IDs):
    --agent task <title>     Create task (auto task-id + session-id)
    --agent supervisor       Register supervisor (auto session-id)

EXAMPLES:
    create --event "git:commit" "fix: login bug"
    create --task "login-fix" "Fix login bug" --need "tests pass"
    create --agent task "Fix the login bug" --need "tests pass"
    create --agent supervisor
EOF
}

# Ensure log and tasks dir exist
touch "$WORLD_LOG"
mkdir -p "$TASKS_DIR"

# Generate timestamp
timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Generate short ID from UUID (first 8 chars)
generate_task_id() {
    uuidgen | tr '[:upper:]' '[:lower:]' | cut -c1-8
}

# Generate full UUID for session
generate_session_id() {
    uuidgen | tr '[:upper:]' '[:lower:]'
}

# Create task markdown file
create_task_md() {
    local task_id="$1"
    local session_id="$2"
    local title="$3"
    local wait="$4"
    local need="$5"
    
    local task_file="$TASKS_DIR/$task_id.md"
    
    if [ -f "$task_file" ]; then
        echo "Error: Task '$task_id' already exists" >&2
        exit 1
    fi
    
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
    
    echo "$task_file"
}

# Parse arguments
if [ $# -lt 1 ]; then
    show_help
    exit 1
fi

case "$1" in
    --event)
        shift
        if [ $# -lt 1 ]; then
            echo "Error: --event requires <type> and <content>" >&2
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
            echo "Error: --event requires <content>" >&2
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
            echo "Error: --task requires <id> <title>" >&2
            exit 1
        fi

        task_id="$1"
        title="$2"
        shift 2

        # Validate task_id format
        if ! [[ "$task_id" =~ ^[a-zA-Z0-9-]+$ ]]; then
            echo "Error: Task ID must be alphanumeric with dashes only" >&2
            exit 1
        fi

        # Parse optional parameters
        wait="-"
        need="-"
        while [ $# -gt 0 ]; do
            case "$1" in
                --wait) wait="$2"; shift 2 ;;
                --need) need="$2"; shift 2 ;;
                *) echo "Error: Unknown option '$1'" >&2; exit 1 ;;
            esac
        done

        session_id=$(generate_session_id)
        task_file=$(create_task_md "$task_id" "$session_id" "$title" "$wait" "$need")

        echo "✓ Created task: tasks/$task_id.md"
        echo "  task_id: $task_id"
        echo "  session_id: $session_id"
        ;;

    --agent)
        shift
        if [ $# -lt 1 ]; then
            echo "Error: --agent requires 'task' or 'supervisor'" >&2
            exit 1
        fi

        agent_type="$1"
        shift

        case "$agent_type" in
            task)
                if [ $# -lt 1 ]; then
                    echo "Error: --agent task requires <title>" >&2
                    exit 1
                fi

                title="$1"
                shift

                # Parse optional parameters
                wait="-"
                need="-"
                while [ $# -gt 0 ]; do
                    case "$1" in
                        --wait) wait="$2"; shift 2 ;;
                        --need) need="$2"; shift 2 ;;
                        *) echo "Error: Unknown option '$1'" >&2; exit 1 ;;
                    esac
                done

                task_id=$(generate_task_id)
                session_id=$(generate_session_id)
                task_file=$(create_task_md "$task_id" "$session_id" "$title" "$wait" "$need")

                # Log agent creation
                entry="[$timestamp] [event] agent:task:start:$session_id | $title"
                echo "$entry" >> "$WORLD_LOG"

                echo "✓ Created task agent"
                echo "  task_id: $task_id"
                echo "  session_id: $session_id"
                echo "  file: tasks/$task_id.md"
                ;;

            supervisor)
                session_id=$(generate_session_id)

                # Log supervisor registration
                entry="[$timestamp] [event] agent:supervisor:start:$session_id | Supervisor registered"
                echo "$entry" >> "$WORLD_LOG"

                echo "✓ Registered supervisor"
                echo "  session_id: $session_id"
                ;;

            *)
                echo "Error: Unknown agent type '$agent_type'. Use 'task' or 'supervisor'" >&2
                exit 1
                ;;
        esac
        ;;

    help|-h|--help)
        show_help
        ;;

    *)
        echo "Error: Unknown option '$1'" >&2
        echo "Run 'world create --help' for usage" >&2
        exit 1
        ;;
esac
