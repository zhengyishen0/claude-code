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
  memory search "<keywords>"
  memory recall <session-id> [<session-id>...] "<question>"

COMMANDS
  search    Find sessions by keywords (ranked by match count)
  recall    Ask session(s) a question (uses haiku, parallel)

EXAMPLES
  memory search "browser automation"
  memory recall abc123 "how was the bug fixed?"
  memory recall abc123 def456 "what was discussed?"

TIPS
  - Use underscore for phrases: memory_tool matches "memory tool"
  - Keywords are OR'd together, ranked by match count
  - Session IDs can be partial (first 7 chars)

EOF
}

case "${1:-}" in
  search)
    shift
    "$SCRIPT_DIR/search.sh" "$@"
    ;;
  recall)
    shift
    "$SCRIPT_DIR/recall.sh" "$@"
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
