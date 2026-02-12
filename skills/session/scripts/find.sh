#!/usr/bin/env bash
# find.sh - Find Claude session by partial ID
# Usage: find.sh <partial> [--path]

set -euo pipefail

partial="$1"
show_path="${2:-}"

if [[ -z "$partial" ]]; then
    echo "Usage: find.sh <partial> [--path]" >&2
    exit 1
fi

# Search all projects
all_matches=()
all_paths=()

while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    name=$(basename "$file" .jsonl)
    if [[ "$name" == *"$partial"* ]]; then
        all_matches+=("$name")
        all_paths+=("$file")
    fi
done < <(find ~/.claude/projects -name "*.jsonl" -type f 2>/dev/null | xargs ls -t 2>/dev/null)

count=${#all_matches[@]}

if [[ "$count" -eq 0 ]]; then
    echo "No session matching '$partial'" >&2
    exit 1
elif [[ "$count" -gt 1 ]]; then
    echo "Multiple sessions match '$partial':" >&2
    for i in "${!all_matches[@]}"; do
        [[ $i -ge 5 ]] && break
        file="${all_paths[$i]}"
        date=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$file" 2>/dev/null || echo "?")
        size=$(stat -f "%z" "$file" 2>/dev/null | awk '{printf "%.0fk", $1/1024}')
        echo "  ${all_matches[$i]:0:12}... ($date, $size)" >&2
    done
    [[ "$count" -gt 5 ]] && echo "  ... and $((count - 5)) more" >&2
    exit 1
fi

if [[ "$show_path" == "--path" ]]; then
    echo "${all_matches[0]}"
    echo "${all_paths[0]}"
else
    echo "${all_matches[0]}"
fi
