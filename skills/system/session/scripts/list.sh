#!/usr/bin/env bash
# list.sh - List recent Claude sessions with summaries
# Usage: list.sh [n]

limit="${1:-10}"
current_project=$(pwd | sed 's|/|-|g')
sessions_dir="$HOME/.claude/projects/$current_project"

# Colors
DIM='\033[0;90m'
NC='\033[0m'
BLUE='\033[0;34m'

if [[ ! -d "$sessions_dir" ]]; then
    echo "  (no sessions)"
    exit 0
fi

# Get recent session files
count=0
for file in $(ls -t "$sessions_dir"/*.jsonl 2>/dev/null); do
    [[ $count -ge $limit ]] && break
    ((count++))

    name=$(basename "$file" .jsonl)
    short_id="${name:0:8}"

    # Get date
    date=$(stat -f "%Sm" -t "%m-%d %H:%M" "$file" 2>/dev/null || echo "?")

    # Extract first user message as summary (truncate to 50 chars)
    summary=$(grep -m1 '"type":"user"' "$file" 2>/dev/null | \
        sed -n 's/.*"content":"\([^"]*\)".*/\1/p' | \
        head -1 | \
        cut -c1-50 | \
        tr '\n' ' ') || true

    # Fallback: try to get content from array format
    if [[ -z "$summary" ]]; then
        summary=$(grep -m1 '"type":"user"' "$file" 2>/dev/null | \
            sed -n 's/.*"text":"\([^"]*\)".*/\1/p' | \
            head -1 | \
            cut -c1-50 | \
            tr '\n' ' ') || true
    fi

    # Clean up summary
    summary="${summary//\\n/ }"
    [[ ${#summary} -eq 50 ]] && summary="${summary}..."
    [[ -z "$summary" ]] && summary="(no prompt)"

    printf "${BLUE}%s${NC}  ${DIM}%s${NC}  %s\n" "$short_id" "$date" "$summary"
done

exit 0
