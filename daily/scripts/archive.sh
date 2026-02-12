#!/bin/bash
# Archive a completed or dropped task
# Usage: ./archive.sh <task-id>

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKFLOW_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(dirname "$WORKFLOW_DIR")"
# Resolve symlink to real path
VAULT_DIR="$(cd "$PROJECT_ROOT/vault" && pwd -P)"

TASK_ID="$1"

if [[ -z "$TASK_ID" ]]; then
    echo "Usage: $0 <task-id>"
    exit 1
fi

TASK_DIR="$VAULT_DIR/active/$TASK_ID"
ARCHIVE_DIR="$VAULT_DIR/archive/$TASK_ID"

if [[ ! -d "$TASK_DIR" ]]; then
    echo "Error: Task not found: $TASK_DIR"
    exit 1
fi

# Check task status
TASK_FILE="$TASK_DIR/task.md"
if [[ -f "$TASK_FILE" ]]; then
    STATUS=$(grep -m1 "^status:" "$TASK_FILE" | sed 's/status: *//')
    if [[ "$STATUS" != "done" && "$STATUS" != "dropped" ]]; then
        echo "Task status is '$STATUS', not 'done' or 'dropped'. Continue anyway? (y/n)"
        read -r REPLY
        if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
            exit 0
        fi
    fi
fi

# Move to archive
mv "$TASK_DIR" "$ARCHIVE_DIR"
echo "Archived: $TASK_ID"

# Update index.md
echo "Remember to update vault/index.md"
