#!/bin/bash
# Process a new raw note into the IVDX system
# Usage: ./new-note.sh <path-to-note.md>
#
# Title (filename) IS the idea. Content is optional context.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKFLOW_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(dirname "$WORKFLOW_DIR")"
# Resolve symlink to real path
VAULT_DIR="$(cd "$PROJECT_ROOT/vault" && pwd -P)"

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
LAST_NUM=$(ls -d "$VAULT_DIR/active/"*/ 2>/dev/null | grep -oE '[0-9]+' | sort -n | tail -1 || echo "0")
NEXT_NUM=$(printf "%03d" $((${LAST_NUM:-0} + 1)))

# Title = filename without extension
TITLE=$(basename "$NOTE_PATH" .md)

# Skip untitled/empty title files
if [[ "$TITLE" == "Untitled" || "$TITLE" == "untitled" || -z "$TITLE" ]]; then
    echo "Skipping: no real title yet"
    exit 0
fi

# Create slug from title
SLUG=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd '[:alnum:]-' | cut -c1-30)
[[ -z "$SLUG" ]] && SLUG="untitled"

TASK_ID="${NEXT_NUM}-${SLUG}"
TASK_DIR="$VAULT_DIR/active/$TASK_ID"

echo "Task ID: $TASK_ID"
echo "Title:   $TITLE"

# Create task directory
mkdir -p "$TASK_DIR"

# Get content (may be empty)
NOTE_CONTENT=$(cat "$NOTE_PATH" 2>/dev/null || echo "")

# Build the idea text: title first, then content if any
if [[ -n "$NOTE_CONTENT" ]]; then
    IDEA="$TITLE

$NOTE_CONTENT"
else
    IDEA="$TITLE"
fi

# Load the intention prompt
PROMPT=$(cat "$WORKFLOW_DIR/prompts/intention.md")

# Call claude in headless mode with the prompt
echo "Calling Claude..."
claude -p --dangerously-skip-permissions --append-system-prompt "$PROMPT" \
    "New note detected. Process into IVDX task.

Task ID: $TASK_ID
Task directory: $TASK_DIR

Raw idea:
---
$IDEA
---

Create task.md and intention.1.md following the system prompt instructions."

# Delete original note after processing
rm "$NOTE_PATH"
echo "Processed and removed: $NOTE_PATH"
