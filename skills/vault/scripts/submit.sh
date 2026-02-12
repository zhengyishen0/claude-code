#!/bin/bash
# Continue working on a submitted task
# Usage: ./submit.sh <path-to-task.md>

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(dirname "$(dirname "$SKILL_DIR")")"
VAULT_DIR="$(cd "$PROJECT_ROOT/vault" && pwd -P)"

DOC_PATH="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"

if [[ -z "$1" || ! -f "$DOC_PATH" ]]; then
    echo "Usage: $0 <path-to-task.md>"
    exit 1
fi

# Only process files in tasks/ folder
REL_PATH="${DOC_PATH#$VAULT_DIR/}"
if [[ "$REL_PATH" != tasks/*.md ]]; then
    echo "Skipping: not in tasks/"
    exit 0
fi

TASK_ID=$(basename "$DOC_PATH" .md)
STATUS=$(grep -m1 "^status:" "$DOC_PATH" | sed 's/status: *//')

echo "Task: $TASK_ID ($STATUS)"

if [[ "$STATUS" == "done" || "$STATUS" == "dropped" ]]; then
    echo "Task already $STATUS"
    exit 0
fi

PROMPT=$(cat "$SKILL_DIR/prompts/assessment.md")

cd "$VAULT_DIR"
claude -p --dangerously-skip-permissions --model claude-opus-4-5 --append-system-prompt "$PROMPT" \
    "Continue task: $TASK_ID
File: $DOC_PATH
Resources: vault/files/$TASK_ID/

Read task, check feedback, continue working."
