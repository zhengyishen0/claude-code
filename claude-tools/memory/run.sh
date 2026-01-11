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
  memory recall [--resume] "<session-id>:<question>" [...]

COMMANDS
  search "OR terms" --and "AND terms" [options]
      Search all sessions with boolean logic.

      Arguments:
        First arg (required)   OR terms - broaden search with synonyms
        --and (required)       AND terms - narrow by requiring these
        --not (optional)       NOT terms - exclude sessions with these

      Flags:
        --sessions N           Sessions to show (default: 5)
        --messages N           Messages per session (default: 5)
        --context N            Characters per snippet (default: 300)
        --recall "question"    Ask matching sessions a question (parallel)

      Phrase support:
        Use underscore to join words: reset_windows matches "reset windows"

      Examples:
        memory search "asus laptop" --and "spec"
        memory search "chrome playwright" --and "click" --not "test"
        memory search "ollama devstral" --and "slow" --recall "What problems?"

  recall [--resume] "<session-id>:<question>" [...]
      Consult a session by forking it and asking a question.
      By default, creates a fresh fork for each recall.

      Flags:
        --resume, -r    Reuse existing fork for follow-up questions

      Examples:
        memory recall "abc-123:How did you handle errors?"
        memory recall --resume "abc-123:Follow-up question"
        memory recall "session1:q1" "session2:q2"  # parallel

WORKFLOW
  1. Search for relevant sessions:
     $ memory search "authentication" --and "error"

  2. Pick a session and ask questions:
     $ memory recall "abc-123:How did you implement JWT?"

  3. Or search + recall in one step:
     $ memory search "auth" --and "jwt" --recall "How was JWT implemented?"

TECHNICAL NOTES
  - Index: claude-tools/memory/data/memory-index.tsv
  - Sessions: ~/.claude/projects/ (read-only, managed by Claude Code)
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
    [ $# -eq 0 ] && { echo "Usage: memory recall [--resume] \"<session-id>:<question>\" [...]" >&2; exit 1; }
    "$SCRIPT_DIR/recall.sh" "$@"
    ;;

  "")
    show_help
    ;;

  *)
    echo "Unknown command: $1" >&2
    echo "Run 'claude-tools memory' for usage" >&2
    exit 1
    ;;
esac
