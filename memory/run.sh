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
  memory search "<keywords>" --recall "<question>"

WORKFLOW
  1. Search first to find relevant sessions
  2. If snippets answer your question, you're done
  3. If you need deeper answers, use --recall

EXAMPLES
  memory search "browser automation"              # broad search
  memory search "browser click"                   # refined search
  memory search "browser click" --recall "how?"   # recall after refining

TIPS
  - Search snippets may be enough - don't always use --recall
  - Use underscore for phrases: memory_tool matches "memory tool"
  - Keywords are OR'd together, ranked by match count

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
