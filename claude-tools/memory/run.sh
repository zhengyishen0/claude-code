#!/bin/bash
# Memory tool - Cross-session knowledge sharing for Claude Code
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Show help
show_help() {
  cat << 'EOF'
memory - Cross-session knowledge sharing for Claude Code

USAGE
  memory search "OR terms" --and "AND terms" [--not "NOT terms"] [--recall "question"]
  memory recall [--new] "<session-id>:<question>" [...]

COMMANDS
  search "OR terms" --and "AND terms" [options]
      Search all sessions with boolean logic.

      Arguments:
        First arg (required)   OR terms - broaden search with synonyms
        --and (required)       AND terms - narrow by requiring these
        --not (optional)       NOT terms - exclude sessions with these

      Flags:
        --limit N              Sessions to show (default: 5)
        --recall "question"    Ask matching sessions a question (parallel)

      Phrase support:
        Use underscore to join words: reset_windows matches "reset windows"

      Examples:
        memory search "asus laptop" --and "spec"
        memory search "chrome playwright" --and "click" --not "test"
        memory search "ollama devstral" --and "slow" --recall "What problems?"

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
     $ memory search "authentication" --and "error"

  2. Pick a session and ask questions:
     $ memory recall "abc-123:How did you implement JWT?"

  3. Or search + recall in one step:
     $ memory search "auth" --and "jwt" --recall "How was JWT implemented?"

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
