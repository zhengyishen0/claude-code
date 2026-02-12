#!/bin/bash
# Process a new raw note into the IVDX system
# Usage: ./new-note.sh <path-to-note.md>
#
# Creates: vault/tasks/NNN-slug.md
# Creates: vault/resources/NNN-slug/ (if needed)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKFLOW_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(dirname "$WORKFLOW_DIR")"
VAULT_DIR="$(cd "$PROJECT_ROOT/vault" && pwd -P)"

# Get absolute path for note
NOTE_PATH="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"

if [[ -z "$1" ]]; then
    echo "Usage: $0 <path-to-note.md>"
    exit 1
fi

if [[ ! -f "$NOTE_PATH" ]]; then
    echo "Error: File not found: $NOTE_PATH"
    exit 1
fi

# Title = filename without extension
TITLE=$(basename "$NOTE_PATH" .md)

# Skip untitled files
if [[ "$TITLE" == "Untitled" || "$TITLE" == "untitled" || -z "$TITLE" ]]; then
    echo "Skipping: no real title yet"
    exit 0
fi

# Get next task number from tasks/ folder
LAST_NUM=$(ls "$VAULT_DIR/tasks/"*.md 2>/dev/null | grep -oE '[0-9]+' | sort -n | tail -1 || echo "0")
NEXT_NUM=$(printf "%03d" $((${LAST_NUM:-0} + 1)))

echo "Title:    $TITLE"
echo "Next ID:  $NEXT_NUM"

# Get content
NOTE_CONTENT=$(cat "$NOTE_PATH" 2>/dev/null || echo "")

if [[ -n "$NOTE_CONTENT" ]]; then
    IDEA="$TITLE

$NOTE_CONTENT"
else
    IDEA="$TITLE"
fi

# Load prompt
PROMPT=$(cat "$WORKFLOW_DIR/prompts/intention.md")

# Call claude (from vault dir)
echo "Calling Claude..."
cd "$VAULT_DIR"
claude -p --dangerously-skip-permissions --model claude-opus-4-5 --append-system-prompt "$PROMPT" \
    "New note detected. Process into IVDX task(s).

Vault directory: $VAULT_DIR
Next task number: $NEXT_NUM

Raw note:
---
$IDEA
---

Create task file(s) in vault/tasks/ as NNN-slug.md
Create resources folder(s) in vault/resources/NNN-slug/ if needed
Update vault/index.md"

# Delete original note
rm "$NOTE_PATH"
echo "Processed and removed: $NOTE_PATH"
