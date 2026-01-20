#!/usr/bin/env bash
# task/run.sh - Task management

set -euo pipefail

: "${PROJECT_DIR:?PROJECT_DIR not set - source env.sh}"

TASKS_DIR="$PROJECT_DIR/tasks"

show_help() {
    cat <<'HELP'
task - Task management

COMMANDS:
    task create <title>     Create a new task
    task list               List all tasks
    task show <id>          Show task details

OPTIONS (for create):
    --wait <cond>           Wait condition (default: "-")
    --need <criteria>       Success criteria (default: "-")

EXAMPLES:
    task create "Fix the login bug"
    task create "Add auth" --need "tests pass"
    task list
    task show abc12345
HELP
}

cmd_create() {
    if [ $# -lt 1 ]; then
        echo "Usage: task create <title> [--wait <cond>] [--need <criteria>]" >&2
        exit 1
    fi

    local title="$1"
    shift

    # Parse options
    local wait="-"
    local need="-"
    while [ $# -gt 0 ]; do
        case "$1" in
            --wait) wait="$2"; shift 2 ;;
            --need) need="$2"; shift 2 ;;
            *) echo "Error: Unknown option '$1'" >&2; exit 1 ;;
        esac
    done

    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local session_id=$(uuidgen | tr '[:upper:]' '[:lower:]')
    local task_id="${session_id:0:8}"
    local task_file="$TASKS_DIR/$task_id.md"

    mkdir -p "$TASKS_DIR"

    cat > "$task_file" << TASK
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

## Progress
- [ ] Started

TASK

    echo "Created: tasks/$task_id.md"
    echo "  title: $title"
    echo "  session: $session_id"
}

cmd_list() {
    if [ ! -d "$TASKS_DIR" ] || [ -z "$(ls -A "$TASKS_DIR" 2>/dev/null)" ]; then
        echo "No tasks found."
        return
    fi

    # Check for yq
    if ! command -v yq >/dev/null 2>&1; then
        echo "Error: yq required. Install with: brew install yq" >&2
        exit 1
    fi

    printf "%-10s %-12s %-40s\n" "ID" "STATUS" "TITLE"
    printf "%-10s %-12s %-40s\n" "--------" "----------" "----------------------------------------"

    for task_file in "$TASKS_DIR"/*.md; do
        [ -e "$task_file" ] || continue

        local id=$(yq eval --front-matter=extract '.id' "$task_file" 2>/dev/null || echo "?")
        local status=$(yq eval --front-matter=extract '.status' "$task_file" 2>/dev/null || echo "?")
        local title=$(yq eval --front-matter=extract '.title' "$task_file" 2>/dev/null || echo "?")

        # Truncate title if too long
        if [ ${#title} -gt 40 ]; then
            title="${title:0:37}..."
        fi

        printf "%-10s %-12s %-40s\n" "$id" "$status" "$title"
    done
}

cmd_show() {
    if [ $# -lt 1 ]; then
        echo "Usage: task show <id>" >&2
        exit 1
    fi

    local task_id="$1"
    local task_file="$TASKS_DIR/$task_id.md"

    if [ ! -f "$task_file" ]; then
        echo "Error: Task not found: $task_id" >&2
        exit 1
    fi

    cat "$task_file"
}

# Ensure tasks directory exists
mkdir -p "$TASKS_DIR"

# Route commands
case "${1:-help}" in
    create)
        shift
        cmd_create "$@"
        ;;
    list|ls)
        cmd_list
        ;;
    show)
        shift
        cmd_show "$@"
        ;;
    help|-h|--help)
        show_help
        ;;
    *)
        echo "Unknown command: $1" >&2
        show_help
        exit 1
        ;;
esac
