#!/usr/bin/env bash
# list.sh - List recent Claude sessions
# Usage: list.sh [n]

set -euo pipefail

limit="${1:-10}"
current_project=$(pwd | sed 's|/|_|g; s|^_|-|')
sessions_dir="$HOME/.claude/projects/$current_project"

echo "Recent sessions (current project):"
if [[ -d "$sessions_dir" ]]; then
    ls -t "$sessions_dir"/*.jsonl 2>/dev/null | head -"$limit" | while read -r file; do
        name=$(basename "$file" .jsonl)
        date=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$file" 2>/dev/null || echo "?")
        size=$(stat -f "%z" "$file" 2>/dev/null | awk '{printf "%.0fk", $1/1024}')
        echo "  ${name:0:12}... ($date, $size)"
    done
else
    echo "  (no sessions)"
fi
