#!/bin/bash
# Memory tool - Cross-session knowledge sharing for Claude Code
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Debug options (documented in code only):
#   --sessions N     Number of sessions to show (default: 10)
#   --messages N     Messages per session (default: 5)
#   --context N      Characters per snippet (default: 300)

show_help() {
  cat << 'EOF'
memory - Cross-session knowledge sharing for Claude Code

USAGE
  memory search "<keywords>" [--recall "question"]

EXAMPLES
  memory search "browser automation"
  memory search "error debug" --recall "how was it fixed?"

OPTIONS
  --recall "Q"     Ask matching sessions a question (parallel)

TIPS
  - Use underscore for phrases: memory_tool matches "memory tool"
  - Keywords are OR'd together, ranked by match count

DIRECT SESSION QUERY
  To ask a specific session directly (without search):
  $ claude --model haiku --resume "session-id" -p "question" --no-session-persistence

EOF
}

case "${1:-}" in
  search)
    shift
    "$SCRIPT_DIR/search.sh" "$@"
    ;;
  ""|--help|-h)
    show_help
    ;;
  *)
    echo "Unknown command: $1" >&2
    echo "Run 'memory' for help" >&2
    exit 1
    ;;
esac
