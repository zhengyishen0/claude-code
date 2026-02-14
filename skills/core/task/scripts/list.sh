#!/usr/bin/env bash
# List tasks
set -euo pipefail

VAULT_DIR="${ZENIX_VAULT:-$HOME/.zenix/vault}"
TASKS_DIR="$VAULT_DIR/Tasks"

if [[ ! -d "$TASKS_DIR" ]]; then
    echo "No tasks directory: $TASKS_DIR" >&2
    exit 0
fi

# Find all task files
for f in "$TASKS_DIR"/*.md "$TASKS_DIR"/*/task.md; do
    [[ -f "$f" ]] || continue

    # Get task ID from path
    if [[ "$f" == */task.md ]]; then
        id=$(basename "$(dirname "$f")")
    else
        id=$(basename "$f" .md)
    fi

    # Get first non-empty line after frontmatter as summary
    summary=$(awk '/^---$/{if(++n==2){f=1;next}}f && /[^ ]/{print; exit}' "$f" | head -c 60)
    [[ ${#summary} -eq 60 ]] && summary="${summary}..."

    printf "%-20s %s\n" "$id" "${summary:-(no description)}"
done
