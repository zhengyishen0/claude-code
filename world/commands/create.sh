#!/usr/bin/env bash
# world/commands/create.sh - Create task markdown files

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Use env vars from shell-init.sh, fallback to script-relative paths
: "${TASKS_DIR:=$SCRIPT_DIR/../tasks}"

show_help() {
    cat <<'HELP'
create - Create a task markdown file

USAGE:
    world create <title> [--wait <cond>] [--need <criteria>]

ARGUMENTS:
    <title>    Task title/description

OPTIONS:
    --wait <cond>      Wait condition (default: "-")
    --need <criteria>  Success criteria (default: "-")

EXAMPLES:
    world create "Fix the login bug"
    world create "Add authentication" --need "tests pass"

NOTE:
    Task ID is auto-generated from session UUID (first 8 chars).
HELP
}

mkdir -p "$TASKS_DIR"

if [ $# -lt 1 ] || [ "$1" = "help" ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

title="$1"
shift

# Parse options
wait="-"
need="-"
while [ $# -gt 0 ]; do
    case "$1" in
        --wait) wait="$2"; shift 2 ;;
        --need) need="$2"; shift 2 ;;
        *) echo "Error: Unknown option '$1'" >&2; exit 1 ;;
    esac
done

timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
session_id=$(uuidgen | tr '[:upper:]' '[:lower:]')
task_id="${session_id:0:8}"

task_file="$TASKS_DIR/$task_id.md"

# Write MD only - watch.sh will sync to log
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
