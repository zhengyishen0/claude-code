#!/bin/bash
# Archive a completed or dropped task
# Usage: ./archive.sh <task-id>
#
# Moves: vault/tasks/NNN-slug.md → vault/archive/NNN-slug.md
# Moves: vault/files/NNN-slug/  → vault/archive/NNN-slug/

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(dirname "$(dirname "$SKILL_DIR")")"
VAULT_DIR="$(cd "$PROJECT_ROOT/vault" && pwd -P)"

TASK_ID="$1"

if [[ -z "$TASK_ID" ]]; then
    echo "Usage: $0 <task-id>"
    exit 1
fi

TASK_FILE="$VAULT_DIR/tasks/$TASK_ID.md"
FILES_DIR="$VAULT_DIR/files/$TASK_ID"

if [[ ! -f "$TASK_FILE" ]]; then
    echo "Error: Task not found: $TASK_FILE"
    exit 1
fi

# Check task status
STATUS=$(grep -m1 "^status:" "$TASK_FILE" | sed 's/status: *//')
if [[ "$STATUS" != "done" && "$STATUS" != "dropped" ]]; then
    echo "Task status is '$STATUS', not 'done' or 'dropped'. Continue anyway? (y/n)"
    read -r REPLY
    if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
        exit 0
    fi
fi

# Create archive dir if needed
mkdir -p "$VAULT_DIR/archive"

# Move task file
mv "$TASK_FILE" "$VAULT_DIR/archive/$TASK_ID.md"
echo "Archived: tasks/$TASK_ID.md"

# Move files dir if exists
if [[ -d "$FILES_DIR" ]]; then
    mv "$FILES_DIR" "$VAULT_DIR/archive/$TASK_ID"
    echo "Archived: files/$TASK_ID/"
fi

echo "Remember to update vault/index.md"
