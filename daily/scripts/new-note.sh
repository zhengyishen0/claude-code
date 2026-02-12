#!/bin/bash
# Process a new raw note into the IVDX system
# Usage: ./new-note.sh <path-to-note.md>
#
# Note may contain ONE or MULTIPLE ideas. AI will split if needed.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKFLOW_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(dirname "$WORKFLOW_DIR")"
# Resolve symlink to real path
VAULT_DIR="$(cd "$PROJECT_ROOT/vault" && pwd -P)"

# Get absolute path for note (before cd'ing later)
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

# Skip untitled/empty title files
if [[ "$TITLE" == "Untitled" || "$TITLE" == "untitled" || -z "$TITLE" ]]; then
    echo "Skipping: no real title yet"
    exit 0
fi

# Get next task number (AI will use this as starting point)
LAST_NUM=$(ls -d "$VAULT_DIR/active/"*/ 2>/dev/null | grep -oE '[0-9]+' | sort -n | tail -1 || echo "0")
NEXT_NUM=$(printf "%03d" $((${LAST_NUM:-0} + 1)))

echo "Title:    $TITLE"
echo "Next ID:  $NEXT_NUM"

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

# Call claude in headless mode with the prompt (from vault dir)
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

Analyze the note:
1. If MULTIPLE distinct ideas → create multiple task folders starting from $NEXT_NUM
2. If SINGLE idea → create one task folder $NEXT_NUM-slug

For each task, create task.md and intention.1.md.
Update vault/index.md with all new tasks."

# Delete original note after processing
rm "$NOTE_PATH"
echo "Processed and removed: $NOTE_PATH"
