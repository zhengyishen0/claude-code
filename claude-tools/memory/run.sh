#!/bin/bash
# Memory tool - Cross-session knowledge sharing for Claude Code
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Show help
show_help() {
  cat << 'EOF'
memory - Cross-session knowledge sharing for Claude Code

USAGE
  claude-tools memory search [--all] "<query>"
  claude-tools memory recall [--new] [--model=MODEL] "<session-id>:<question>" [...]

COMMANDS
  search [--all] "<query>"
      Search all sessions with boolean logic.

      Flags:
        --all, -a    Show all matches (no truncation)

      Query syntax:
        term1|term2    OR  (first term, rg pattern)
        term           AND (space-separated)
        -term          NOT (dash prefix)

      Examples:
        memory search "error"
        memory search "chrome|playwright"
        memory search --all "chrome|playwright click -test"

  recall [--new] [--model=MODEL] "<session-id>:<question>" [...]
      Consult a session by forking it and asking a question.

      Flags:
        --new, -n         Force new fork (ignore existing)
        --model=MODEL     Model to use (default: haiku)
                          Options: haiku, sonnet, opus

      Examples:
        # Single query (uses haiku by default)
        memory recall "abc-123:How did you handle errors?"

        # Force new fork
        memory recall --new "abc-123:Start fresh question"

        # Use a different model
        memory recall --model=sonnet "abc-123:Complex question"

        # Multiple queries (parallel)
        memory recall "session1:question1" "session2:question2"

WORKFLOW
  1. Search for relevant sessions:
     $ claude-tools memory search "authentication"

  2. Pick a session from results and ask questions:
     $ claude-tools memory recall "abc-123:How did you implement JWT?"

  3. Follow-up questions reuse the same fork:
     $ claude-tools memory recall "abc-123:What about refresh tokens?"

  4. Start fresh when needed:
     $ claude-tools memory recall --new "abc-123:Different topic"

TECHNICAL NOTES
  - Index: ~/.claude/memory-index.tsv
  - Fork state: ~/.claude/memory-state/<session-id>.fork
  - First search builds index (~12s), subsequent searches ~0.5s
  - Recall uses haiku by default (fast, cheap)

REQUIREMENTS
  - ripgrep (rg)
  - jq
  - Claude Code CLI

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
    [ $# -eq 0 ] && { echo "Usage: memory recall [--new] [--model=MODEL] \"<session-id>:<question>\" [...]" >&2; exit 1; }
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
