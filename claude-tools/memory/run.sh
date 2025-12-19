#!/bin/bash
# Memory tool - Cross-session knowledge sharing for Claude Code
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Show help
show_help() {
  cat << 'EOF'
memory - Cross-session knowledge sharing for Claude Code

USAGE
  memory search [--limit N] [--raw] "<query>"
  memory recall [--new] "<session-id>:<question>" [...]

COMMANDS
  search [--limit N] [--raw] "<query>"
      Search all sessions with boolean logic.

      Flags:
        --limit N    Messages per session (default: 15)
        --raw        Skip summarization, show raw output

      Query syntax:
        term1|term2    OR  (first term, rg pattern)
        term           AND (space-separated)
        -term          NOT (dash prefix)

      Summarization:
        Results are summarized by default with haiku. Use --raw to skip.

      Examples:
        memory search "error"
        memory search "chrome|playwright"
        memory search --raw "chrome|playwright click -test"

  recall [--new] "<session-id>:<question>" [...]
      Consult a session by forking it and asking a question.

      Flags:
        --new, -n    Force new fork (ignore existing fork)

      Examples:
        memory recall "abc-123:How did you handle errors?"
        memory recall --new "abc-123:Start fresh question"
        memory recall "session1:q1" "session2:q2"  # parallel

WORKFLOW
  1. Search for relevant sessions:
     $ memory search "authentication"

  2. Pick a session and ask questions:
     $ memory recall "abc-123:How did you implement JWT?"

  3. Follow-up (reuses same fork):
     $ memory recall "abc-123:What about refresh tokens?"

  4. Start fresh when needed:
     $ memory recall --new "abc-123:Different topic"

TECHNICAL NOTES
  - Index: ~/.claude/memory-index.tsv
  - Fork state: ~/.claude/memory-state/<session-id>.fork
  - First search builds index (~12s), subsequent ~0.5s

EOF
}

# Main command router
case "${1:-}" in
  search)
    shift
    "$SCRIPT_DIR/search.sh" "$@"
    ;;

  recall)
    shift
    [ $# -eq 0 ] && { echo "Usage: memory recall [--new] \"<session-id>:<question>\" [...]" >&2; exit 1; }
    "$SCRIPT_DIR/recall.sh" "$@"
    ;;

  --help|-h|help|"")
    show_help
    ;;

  *)
    echo "Unknown command: $1" >&2
    echo "Run 'claude-tools memory --help' for usage" >&2
    exit 1
    ;;
esac
