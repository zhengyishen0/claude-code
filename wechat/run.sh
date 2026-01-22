#!/bin/bash
# WeChat search tool - Search chat history from Android emulator
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

show_help() {
  cat << 'EOF'
wechat - Search WeChat chat history from Android emulator

USAGE
  wechat "<query>"          Search messages (auto-setup on first run)
  wechat sync               Refresh database from emulator

EXAMPLES
  wechat "meeting tomorrow"   # fuzzy: matches either word
  wechat "from:张三"          # filter by sender
  wechat "type:image"         # filter by type (image/voice/video/file)

FIRST RUN
  On first search, wechat will:
  1. Check dependencies (adb, sqlcipher, frida)
  2. Extract encryption key via Frida (opens WeChat automatically)
  3. Pull and decrypt database
  4. Build search index

  Just make sure your emulator is running with WeChat logged in.

EOF
}

case "${1:-}" in
  sync)
    "$SCRIPT_DIR/init.sh"
    ;;
  --help|-h|"")
    show_help
    ;;
  *)
    # Treat any other argument as a search query
    "$SCRIPT_DIR/search.sh" "$@"
    ;;
esac
