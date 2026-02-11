#!/bin/bash
# Process a submitted document (submit: true) in the IVDX system
# Usage: ./submit.sh <path-to-document.md>

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKFLOW_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(dirname "$WORKFLOW_DIR")"
# Resolve symlink to real path
VAULT_DIR="$(cd "$PROJECT_ROOT/vault" && pwd -P)"

DOC_PATH="$1"

if [[ -z "$DOC_PATH" ]]; then
    echo "Usage: $0 <path-to-document.md>"
    exit 1
fi

if [[ ! -f "$DOC_PATH" ]]; then
    echo "Error: File not found: $DOC_PATH"
    exit 1
fi

# Determine document type from frontmatter
DOC_TYPE=$(grep -m1 "^type:" "$DOC_PATH" | sed 's/type: *//')

# Get task directory
TASK_DIR=$(dirname "$DOC_PATH")
TASK_ID=$(basename "$TASK_DIR")

echo "Processing submitted $DOC_TYPE for task: $TASK_ID"

# Select appropriate prompt based on document type
case "$DOC_TYPE" in
    intention)
        PROMPT=$(cat "$WORKFLOW_DIR/prompts/assessment.md")
        NEXT_STAGE="assessment"
        ;;
    assessment)
        PROMPT=$(cat "$WORKFLOW_DIR/prompts/contract.md")
        NEXT_STAGE="contract"
        ;;
    contract)
        # Check if contract is signed (not just submitted)
        STATUS=$(grep -m1 "^status:" "$DOC_PATH" | sed 's/status: *//')
        if [[ "$STATUS" != "signed" ]]; then
            echo "Contract not signed yet. Waiting for signature."
            exit 0
        fi
        PROMPT=$(cat "$WORKFLOW_DIR/prompts/execution.md")
        NEXT_STAGE="execution"
        ;;
    report)
        echo "Report submitted. Human review needed."
        exit 0
        ;;
    *)
        echo "Unknown document type: $DOC_TYPE"
        exit 1
        ;;
esac

# Call claude in headless mode with the appropriate prompt
claude -p --dangerously-skip-permissions --append-system-prompt "$PROMPT" \
    "Document submitted for task: $TASK_ID

Submitted document: $DOC_PATH
Next stage: $NEXT_STAGE

Read the submitted document and any human feedback, then proceed to $NEXT_STAGE stage."
