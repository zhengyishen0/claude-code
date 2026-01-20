#!/usr/bin/env bash
# world/commands/create.sh
# Create events, tasks, or auto-register agents

set -euo pipefail

# Source paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../paths.sh"

# Ensure directories exist
mkdir -p "$TASKS_DIR"
touch "$WORLD_LOG"

show_help() {
    cat <<'HELP'
create - Add entries to world log

USAGE:
    create --event <type> [--session <id>] <message>
    create --task <id> <title> [--wait <condition>] [--need <requirement>]
    create --agent task <title> [--wait <condition>] [--need <requirement>]
    create --agent supervisor

EVENT TYPES:
    git:commit, git:push, git:merge    Git operations
    system                              System events
    user                                User actions
    <custom>                            Any custom type

TASK CREATION:
    --task <id> <title>                 Create task with explicit ID
    --agent task <title>                Auto-generate task ID and session

EXAMPLES:
    create --event "git:commit" "fix: login bug"
    create --event "system" --session abc123 "task started"
    create --task "login-fix" "Fix login validation"
    create --agent task "Implement dark mode" --need "tests pass"
    create --agent supervisor
HELP
}

# Generate UUIDs
generate_task_id() {
    uuidgen | tr '[:upper:]' '[:lower:]' | cut -d'-' -f1
}

generate_session_id() {
    uuidgen | tr '[:upper:]' '[:lower:]'
}

# Create task markdown file
create_task_md() {
    local task_id="$1"
    local session_id="$2"
    local title="$3"
    local wait="${4:--}"
    local need="${5:--}"
    
    local task_file="$TASKS_DIR/$task_id.md"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    cat > "$task_file" << TASKEOF
---
id: $task_id
session_id: $session_id
title: $title
status: pending
created: $timestamp
wait: $wait
need: $need
---

# $title

## Description

Task created at $timestamp

## Notes

TASKEOF

    echo "$task_file"
}

# Create event entry
do_create_event() {
    local event_type="$1"
    local session_id="$2"
    local message="$3"
    
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local entry="[$timestamp] [event] $event_type"
    
    if [ -n "$session_id" ]; then
        entry="$entry | session: $session_id"
    fi
    
    entry="$entry | $message"
    
    echo "$entry" >> "$WORLD_LOG"
    echo "$entry"
}

# Create task entry
do_create_task() {
    local task_id="$1"
    local title="$2"
    local wait="$3"
    local need="$4"
    
    local session_id=$(generate_session_id)
    local task_file=$(create_task_md "$task_id" "$session_id" "$title" "$wait" "$need")
    
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local entry="[$timestamp] [task: pending] $task_id($title) | file: tasks/$task_id.md | wait: $wait | need: $need"
    
    echo "$entry" >> "$WORLD_LOG"
    echo "Created task: $task_id"
    echo "  File: $task_file"
    echo "  Session: $session_id"
}

# Auto-create agent (task or supervisor)
do_create_agent() {
    local agent_type="$1"
    shift
    
    case "$agent_type" in
        task)
            local title=""
            local wait="-"
            local need="-"
            
            # Parse remaining args
            while [ $# -gt 0 ]; do
                case "$1" in
                    --wait) wait="$2"; shift 2 ;;
                    --need) need="$2"; shift 2 ;;
                    *) 
                        if [ -z "$title" ]; then
                            title="$1"
                        fi
                        shift
                        ;;
                esac
            done
            
            if [ -z "$title" ]; then
                echo "Error: --agent task requires <title>" >&2
                exit 1
            fi
            
            local task_id=$(generate_task_id)
            local session_id=$(generate_session_id)
            local task_file=$(create_task_md "$task_id" "$session_id" "$title" "$wait" "$need")
            
            local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
            local entry="[$timestamp] [task: pending] $task_id($title) | file: tasks/$task_id.md | wait: $wait | need: $need"
            echo "$entry" >> "$WORLD_LOG"
            
            echo "Created task agent: $task_id"
            echo "  Title: $title"
            echo "  File: $task_file"
            echo "  Session: $session_id"
            ;;
        supervisor)
            local session_id=$(generate_session_id)
            local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
            local entry="[$timestamp] [event] agent:supervisor:start:$session_id | Supervisor registered"
            echo "$entry" >> "$WORLD_LOG"
            
            echo "Registered supervisor agent"
            echo "  Session: $session_id"
            echo ""
            echo "Export this to use supervisor commands:"
            echo "  export SUPERVISOR_SESSION_ID=$session_id"
            ;;
        *)
            echo "Error: Unknown agent type: $agent_type" >&2
            echo "Valid types: task, supervisor" >&2
            exit 1
            ;;
    esac
}

# Parse arguments
if [ $# -lt 1 ]; then
    show_help
    exit 0
fi

case "$1" in
    --event)
        shift
        [ $# -lt 1 ] && { echo "Error: --event requires <type>" >&2; exit 1; }
        event_type="$1"
        shift
        
        session_id=""
        if [ "${1:-}" = "--session" ]; then
            shift
            session_id="$1"
            shift
        fi
        
        message="${*:-}"
        [ -z "$message" ] && { echo "Error: --event requires <message>" >&2; exit 1; }
        
        do_create_event "$event_type" "$session_id" "$message"
        ;;
    --task)
        shift
        [ $# -lt 2 ] && { echo "Error: --task requires <id> <title>" >&2; exit 1; }
        task_id="$1"
        title="$2"
        shift 2
        
        wait="-"
        need="-"
        while [ $# -gt 0 ]; do
            case "$1" in
                --wait) wait="$2"; shift 2 ;;
                --need) need="$2"; shift 2 ;;
                *) shift ;;
            esac
        done
        
        do_create_task "$task_id" "$title" "$wait" "$need"
        ;;
    --agent)
        shift
        [ $# -lt 1 ] && { echo "Error: --agent requires <type>" >&2; exit 1; }
        do_create_agent "$@"
        ;;
    help|-h|--help)
        show_help
        ;;
    *)
        echo "Unknown option: $1" >&2
        echo "Run 'world create help' for usage" >&2
        exit 1
        ;;
esac
