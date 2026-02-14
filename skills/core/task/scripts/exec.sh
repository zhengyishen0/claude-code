#!/usr/bin/env bash
# Execute a task by ID
set -euo pipefail

TASK_ID="${1:-}"
if [[ -z "$TASK_ID" ]]; then
    echo "Usage: task exec <task-id>" >&2
    exit 1
fi

VAULT_DIR="${ZENIX_VAULT:-$HOME/.zenix/vault}"
TASKS_DIR="$VAULT_DIR/Tasks"

# ─────────────────────────────────────────────────────────────
# Find task file
# ─────────────────────────────────────────────────────────────

find_task() {
    local id="$1"

    # Exact match: file
    [[ -f "$TASKS_DIR/${id}.md" ]] && echo "$TASKS_DIR/${id}.md" && return 0

    # Exact match: folder
    [[ -f "$TASKS_DIR/${id}/task.md" ]] && echo "$TASKS_DIR/${id}/task.md" && return 0

    # Partial match
    for f in "$TASKS_DIR"/${id}*.md "$TASKS_DIR"/${id}*/task.md; do
        [[ -f "$f" ]] && echo "$f" && return 0
    done

    return 1
}

TASK_FILE=$(find_task "$TASK_ID") || {
    echo "Task not found: $TASK_ID" >&2
    echo "Looking in: $TASKS_DIR" >&2
    exit 1
}

echo "Task: $TASK_FILE" >&2

# ─────────────────────────────────────────────────────────────
# Parse frontmatter
# ─────────────────────────────────────────────────────────────

parse_frontmatter() {
    local file="$1"
    local key="$2"
    grep "^${key}:" "$file" 2>/dev/null | sed "s/${key}:[[:space:]]*//" | head -1
}

get_body() {
    local file="$1"
    awk '/^---$/{if(++n==2){f=1;next}}f' "$file"
}

WORK_PATH=$(parse_frontmatter "$TASK_FILE" "work-path")
AGENT_NAME=$(parse_frontmatter "$TASK_FILE" "agent")

# ─────────────────────────────────────────────────────────────
# Resolve work-path
# ─────────────────────────────────────────────────────────────

if [[ -z "$WORK_PATH" ]]; then
    echo "Error: work-path not specified in task" >&2
    exit 1
fi

# Expand tilde
WORK_PATH="${WORK_PATH/#\~/$HOME}"

# If file, use parent directory
[[ -f "$WORK_PATH" ]] && WORK_PATH=$(dirname "$WORK_PATH")

# Validate
if [[ ! -d "$WORK_PATH" ]]; then
    echo "Error: work-path not found: $WORK_PATH" >&2
    exit 1
fi

echo "Work path: $WORK_PATH" >&2

# ─────────────────────────────────────────────────────────────
# Extract task body and spawn agent
# ─────────────────────────────────────────────────────────────

TASK_BODY=$(get_body "$TASK_FILE")

if [[ -z "$TASK_BODY" ]]; then
    echo "Error: task has no content" >&2
    exit 1
fi

cd "$WORK_PATH"

if [[ -n "$AGENT_NAME" ]]; then
    echo "Agent: $AGENT_NAME" >&2
    exec agent -A "$AGENT_NAME" "$TASK_BODY"
else
    echo "Agent: (default)" >&2
    exec agent "$TASK_BODY"
fi
