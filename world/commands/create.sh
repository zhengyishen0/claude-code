#!/usr/bin/env bash
# world/commands/create.sh
# Create task markdown files

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../paths.sh"

show_help() {
    cat <<'HELP'
create - Create a task markdown file

USAGE:
    world create <id> <title> [--wait <cond>] [--need <criteria>]

ARGUMENTS:
    <id>       Task ID (alphanumeric and dashes only)
    <title>    Task title/description

OPTIONS:
    --wait <cond>      Wait condition (default: "-")
    --need <criteria>  Success criteria (default: "-")

EXAMPLES:
    world create fix-bug "Fix the login bug"
    world create feature-auth "Add authentication" --need "tests pass"
    world create task-123 "Implement feature" --wait "API ready" --need "builds"
HELP
}

# Ensure tasks dir exists
mkdir -p "$TASKS_DIR"

# Generate timestamp
timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Generate full UUID for session
generate_session_id() {
    uuidgen | tr '[:upper:]' '[:lower:]'
}

# Parse arguments
if [ $# -lt 2 ]; then
    show_help
    exit 0
fi

if [ "$1" = "help" ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

task_id="$1"
title="$2"
shift 2

# Validate task_id format
if ! [[ "$task_id" =~ ^[a-zA-Z0-9-]+$ ]]; then
    echo "Error: Task ID must be alphanumeric with dashes only" >&2
    exit 1
fi

# Check if task already exists
task_file="$TASKS_DIR/$task_id.md"
if [ -f "$task_file" ]; then
    echo "Error: Task '$task_id' already exists" >&2
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

# Create task markdown
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

## Wait Condition
$wait

## Success Criteria
$need

## Progress
- [ ] Started

TASK

# Log task creation
"$SCRIPT_DIR/../run.sh" log "task:created:$task_id" "$title"

echo "✓ Created: tasks/$task_id.md"
echo "  session: $session_id"
