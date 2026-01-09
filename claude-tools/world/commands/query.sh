#!/usr/bin/env bash
# claude-tools/world/commands/query.sh
# Common queries on world.log

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORLD_LOG="$SCRIPT_DIR/../world.log"

show_help() {
    cat <<'EOF'
query - Common queries on world.log

USAGE:
    query <type> [pattern]

QUERIES:
    active      All agents with status=active
    pending     Agents with status=finish (awaiting verification)
    failed      Agents with status=failed
    verified    Agents with status=verified
    events      All events (optionally filter by source)
    agent       All entries for a specific agent/session-id
    recent      Last N entries (default 20)

EXAMPLES:
    query active                 # All active agents
    query pending                # Agents awaiting verification
    query failed                 # All failed agents
    query events chrome          # All chrome events
    query agent abc123           # All entries for session abc123
    query recent 50              # Last 50 entries

OUTPUT:
    Matching log entries, or "no matches"
EOF
}

if [ $# -lt 1 ] || [ "${1:-}" = "help" ] || [ "${1:-}" = "-h" ]; then
    show_help
    exit 0
fi

query_type="$1"
pattern="${2:-}"

# Ensure log exists
if [ ! -f "$WORLD_LOG" ]; then
    echo "no matches (log does not exist)"
    exit 0
fi

case "$query_type" in
    active)
        result=$(rg '\[agent:active\]' "$WORLD_LOG" 2>/dev/null || echo "")
        ;;
    pending)
        result=$(rg '\[agent:finish\]' "$WORLD_LOG" 2>/dev/null || echo "")
        ;;
    failed)
        result=$(rg '\[agent:failed\]' "$WORLD_LOG" 2>/dev/null || echo "")
        ;;
    verified)
        result=$(rg '\[agent:verified\]' "$WORLD_LOG" 2>/dev/null || echo "")
        ;;
    events)
        if [ -n "$pattern" ]; then
            result=$(rg "\[event:$pattern\]" "$WORLD_LOG" 2>/dev/null || echo "")
        else
            result=$(rg '\[event:' "$WORLD_LOG" 2>/dev/null || echo "")
        fi
        ;;
    agent)
        if [ -z "$pattern" ]; then
            echo "Usage: query agent <session-id>"
            exit 1
        fi
        result=$(rg "\[$pattern\]" "$WORLD_LOG" 2>/dev/null || echo "")
        ;;
    recent)
        count="${pattern:-20}"
        result=$(tail -n "$count" "$WORLD_LOG" 2>/dev/null || echo "")
        ;;
    *)
        echo "Unknown query type: $query_type"
        echo "Run 'query help' for usage"
        exit 1
        ;;
esac

if [ -z "$result" ]; then
    echo "no matches"
else
    echo "$result"
fi
