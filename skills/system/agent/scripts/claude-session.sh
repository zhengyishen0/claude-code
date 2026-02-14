#!/usr/bin/env bash
# session.sh - Find and list Claude sessions
#
# Usage:
#   session.sh find <partial> [--path]   Find session by partial ID
#   session.sh list [n]                  List recent n sessions (default 10)

set -euo pipefail

# ─────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────

get_date() {
    stat -f "%Sm" -t "$1" "$2" 2>/dev/null || echo "?"
}

# ─────────────────────────────────────────────────────────────
# find - Search all projects for partial ID match
# ─────────────────────────────────────────────────────────────

cmd_find() {
    local partial="${1:-}"
    local show_path="${2:-}"

    if [[ -z "$partial" ]]; then
        echo "Usage: session.sh find <partial> [--path]" >&2
        exit 1
    fi

    local all_matches=()
    local all_paths=()

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        local name
        name=$(basename "$file" .jsonl)
        if [[ "$name" == *"$partial"* ]]; then
            all_matches+=("$name")
            all_paths+=("$file")
        fi
    done < <(find ~/.claude/projects -name "*.jsonl" -type f 2>/dev/null | xargs ls -t 2>/dev/null)

    local count=${#all_matches[@]}

    if [[ "$count" -eq 0 ]]; then
        echo "No session matching '$partial'" >&2
        exit 1
    elif [[ "$count" -gt 1 ]]; then
        echo "Multiple sessions match '$partial':" >&2
        for i in "${!all_matches[@]}"; do
            [[ $i -ge 5 ]] && break
            local file="${all_paths[$i]}"
            local date
            date=$(get_date "%Y-%m-%d %H:%M" "$file")
            local size
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
}

# ─────────────────────────────────────────────────────────────
# list - List recent sessions in current project
# ─────────────────────────────────────────────────────────────

cmd_list() {
    local limit="${1:-10}"
    local current_project
    current_project=$(pwd | sed 's|/|-|g')
    local sessions_dir="$HOME/.claude/projects/$current_project"

    # Colors
    local DIM='\033[0;90m'
    local NC='\033[0m'
    local BLUE='\033[0;34m'

    if [[ ! -d "$sessions_dir" ]]; then
        echo "  (no sessions)"
        exit 0
    fi

    local count=0
    for file in $(ls -t "$sessions_dir"/*.jsonl 2>/dev/null); do
        [[ $count -ge $limit ]] && break
        ((count++))

        local name
        name=$(basename "$file" .jsonl)
        local short_id="${name:0:8}"

        local date
        date=$(get_date "%m-%d %H:%M" "$file")

        # Extract first user message as summary (truncate to 50 chars)
        local summary
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
}

# ─────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────

case "${1:-help}" in
    find)
        cmd_find "${@:2}"
        ;;
    list)
        cmd_list "${@:2}"
        ;;
    -h|--help|help|"")
        cat <<'EOF'
session.sh - Find and list Claude sessions

Usage:
  session.sh find <partial>          Find session, return full ID
  session.sh find <partial> --path   Also return file path
  session.sh list [n]                List recent n sessions

Examples:
  session.sh find abc123
  session.sh find 4ee9 --path
  session.sh list 5
EOF
        ;;
    *)
        echo "Unknown command: $1" >&2
        echo "Usage: session.sh {find|list|help}" >&2
        exit 1
        ;;
esac
