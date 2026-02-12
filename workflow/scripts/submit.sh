#!/bin/bash
# Process a submitted task file in the IVDX system
# Usage: ./submit.sh <path-to-task.md>
#
# Reads status field and proceeds to next stage

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKFLOW_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(dirname "$WORKFLOW_DIR")"
VAULT_DIR="$(cd "$PROJECT_ROOT/vault" && pwd -P)"

# Get absolute path
DOC_PATH="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"

if [[ -z "$1" ]]; then
    echo "Usage: $0 <path-to-task.md>"
    exit 1
fi

if [[ ! -f "$DOC_PATH" ]]; then
    echo "Error: File not found: $DOC_PATH"
    exit 1
fi

# Only process files in tasks/ folder
REL_PATH="${DOC_PATH#$VAULT_DIR/}"
if [[ "$REL_PATH" != tasks/*.md ]]; then
    echo "Skipping: not in tasks/ folder"
    exit 0
fi

# Get task ID from filename (e.g., 001-task-name.md → 001-task-name)
TASK_ID=$(basename "$DOC_PATH" .md)

# Get current status
STATUS=$(grep -m1 "^status:" "$DOC_PATH" | sed 's/status: *//')

echo "Task: $TASK_ID"
echo "Status: $STATUS"

# Select prompt based on status
case "$STATUS" in
    intention)
        PROMPT=$(cat "$WORKFLOW_DIR/prompts/assessment.md")
        NEXT_STAGE="assessment"
        ;;
    assessment)
        PROMPT=$(cat "$WORKFLOW_DIR/prompts/contract.md")
        NEXT_STAGE="decision"
        ;;
    decision)
        PROMPT=$(cat "$WORKFLOW_DIR/prompts/execution.md")
        NEXT_STAGE="execution"
        ;;
    execution|done|dropped)
        echo "Task already $STATUS."
        exit 0
        ;;
    *)
        echo "Unknown status: $STATUS"
        exit 1
        ;;
esac

echo "Next stage: $NEXT_STAGE"

# Call claude
cd "$VAULT_DIR"
claude -p --dangerously-skip-permissions --model claude-opus-4-5 --append-system-prompt "$PROMPT" \
    "Task submitted: $TASK_ID
Task file: $DOC_PATH
Resources folder: vault/resources/$TASK_ID/

Current status: $STATUS
Next stage: $NEXT_STAGE

Read task file, check Human Feedback, fill the $NEXT_STAGE section."
