#!/bin/bash
# Process a new raw note into the IVDX system
# Usage: ./new-note.sh <path-to-note.md>

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKFLOW_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(dirname "$WORKFLOW_DIR")"
VAULT_DIR="$PROJECT_ROOT/vault"

NOTE_PATH="$1"

if [[ -z "$NOTE_PATH" ]]; then
    echo "Usage: $0 <path-to-note.md>"
    exit 1
fi

if [[ ! -f "$NOTE_PATH" ]]; then
    echo "Error: File not found: $NOTE_PATH"
    exit 1
fi

# Get next task number
LAST_NUM=$(ls -d "$VAULT_DIR/active/"*/ 2>/dev/null | grep -oE '[0-9]+' | sort -n | tail -1)
NEXT_NUM=$(printf "%03d" $((${LAST_NUM:-0} + 1)))

# Create slug from filename
FILENAME=$(basename "$NOTE_PATH" .md)
SLUG=$(echo "$FILENAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd '[:alnum:]-')

TASK_ID="${NEXT_NUM}-${SLUG}"
TASK_DIR="$VAULT_DIR/active/$TASK_ID"

echo "Creating task: $TASK_ID"

# Create task directory
mkdir -p "$TASK_DIR"

# Read the note content
NOTE_CONTENT=$(cat "$NOTE_PATH")

# Load the intention prompt
PROMPT=$(cat "$WORKFLOW_DIR/prompts/intention.md")

# Call claude with the prompt
claude --append-system-prompt "$PROMPT" \
    "New note detected. Process into IVDX task.

Task ID: $TASK_ID
Task directory: $TASK_DIR

Raw note content:
---
$NOTE_CONTENT
---

Create task.md and intention.1.md following the system prompt instructions."

# Move original note to processed (or delete)
echo "Task created: $TASK_DIR"
echo "Original note: $NOTE_PATH"
echo "Delete original? (y/n)"
read -r REPLY
if [[ "$REPLY" =~ ^[Yy]$ ]]; then
    rm "$NOTE_PATH"
    echo "Deleted: $NOTE_PATH"
fi
