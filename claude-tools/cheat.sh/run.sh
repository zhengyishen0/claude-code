#!/bin/bash
# cheat.sh - Get concise CLI command examples via cheat.sh API
# Usage: Use curl directly (no wrapper needed)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOL_NAME="$(basename "$SCRIPT_DIR")"

show_help() {
  cat << 'EOF'
cheat.sh - Get concise CLI command examples via cheat.sh API

No wrapper needed - use curl directly for simplicity.

Basic Usage:
  # CLI commands (always use ?T for text-only output)
  curl -s 'cht.sh/tar?T'
  curl -s 'cht.sh/git?T'
  curl -s 'cht.sh/jq?T'

  # Programming languages (use + for spaces)
  curl -s 'cht.sh/python/reverse+list?T'
  curl -s 'cht.sh/javascript/sort+array?T'

Search:
  # Search all cheat sheets
  curl -s 'cht.sh/~keyword?T'

  # Search within language
  curl -s 'cht.sh/python/~closure?T'

Options:
  ?T    Text only, no ANSI colors (recommended)
  ?Q    Code only, no comments
  ?q    Quiet mode

Special Queries:
  curl -s 'cht.sh/python/:list?T'     # List topics
  curl -s 'cht.sh/python/:learn?T'    # Learn language
  curl -s 'cht.sh/:help?T'            # Full help

Coverage: 14,664 topics (CLI + programming languages)
Sources: tldr-pages, cheat.sheets, StackOverflow

Base URL: https://cht.sh/
EOF
}

case "$1" in
  help|--help|-h|"")
    show_help
    ;;
  *)
    echo "Unknown command: $1" >&2
    echo "Run '$TOOL_NAME help' for usage" >&2
    exit 1
    ;;
esac
