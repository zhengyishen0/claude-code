#!/usr/bin/env bash
# session - Find Claude sessions by partial ID
#
# Usage:
#   session find <partial>          # Returns full session ID
#   session find <partial> --path   # Also show file path
#   session list [n]                # List recent n sessions (default 10)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "${1:-help}" in
    find)
        exec "$SCRIPT_DIR/scripts/find.sh" "${@:2}"
        ;;
    list)
        exec "$SCRIPT_DIR/scripts/list.sh" "${@:2}"
        ;;
    -h|--help|help|"")
        cat <<'EOF'
session - Find Claude sessions by partial ID

Usage:
  session find <partial>          Find session, return full ID
  session find <partial> --path   Also return file path
  session list [n]                List recent n sessions

Examples:
  session find abc123
  session find 4ee9 --path
  session list 5
EOF
        ;;
    *)
        echo "Unknown command: $1" >&2
        echo "Usage: session {find|list|help}" >&2
        exit 1
        ;;
esac
