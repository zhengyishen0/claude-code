#!/bin/bash
# Process a submitted document (submit: true) in the IVDX system
# Usage: ./submit.sh <path-to-document.md>

set -e

SKILL_DIR=~/.claude-code/skills/vault
VAULT_DIR="$(cd ~/.claude-code/vault && pwd -P)"

# Get absolute path for doc (before cd'ing later)
DOC_PATH="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"

if [[ -z "$1" ]]; then
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
    intention|eval)
        PROMPT=$(cat "$SKILL_DIR/prompts/assessment.md")
        NEXT_STAGE="assessment"
        ;;
    assessment)
        PROMPT=$(cat "$SKILL_DIR/prompts/contract.md")
        NEXT_STAGE="contract"
        ;;
    contract)
        # Check if contract is signed (not just submitted)
        STATUS=$(grep -m1 "^status:" "$DOC_PATH" | sed 's/status: *//')
        if [[ "$STATUS" != "signed" ]]; then
            echo "Contract not signed yet. Waiting for signature."
            exit 0
        fi
        PROMPT=$(cat "$SKILL_DIR/prompts/execution.md")
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

# Call claude in headless mode with the appropriate prompt (from vault dir)
cd "$VAULT_DIR"
cc -p --append-system-prompt "$PROMPT" \
    "Document submitted for task: $TASK_ID

Submitted document: $DOC_PATH
Next stage: $NEXT_STAGE

Read the submitted document and any human feedback, then proceed to $NEXT_STAGE stage."
