#!/bin/bash
# WeChat search tool - Search chat history from Android emulator
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

show_help() {
  cat << 'EOF'
wechat - Search WeChat chat history from Android emulator

USAGE
  wechat init [key]        Sync database from emulator and build index
  wechat search "<query>"  Search messages (auto-init if needed)

EXAMPLES
  wechat init 73b69e9              # init with decryption key
  wechat search "meeting tomorrow"
  wechat search "from:张三"
  wechat search "type:image"

SEARCH SYNTAX
  "keyword"       Full-text search
  from:name       Filter by sender name
  type:image      Filter by type (image/voice/video/file)

NOTES
  - Requires Android emulator with WeChat running
  - Uses adb to pull encrypted database
  - Decrypts with sqlcipher (cipher_compatibility=1)
  - First search auto-runs init if database not found

EOF
}

case "${1:-}" in
  init)
    shift
    "$SCRIPT_DIR/init.sh" "$@"
    ;;
  search)
    shift
    "$SCRIPT_DIR/search.sh" "$@"
    ;;
  ""|--help|-h)
    show_help
    ;;
  *)
    echo "Unknown command: $1" >&2
    echo "Run 'wechat' for help" >&2
    exit 1
    ;;
esac
