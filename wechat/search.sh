#!/bin/bash
# Search WeChat messages
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$SCRIPT_DIR/data"
DECRYPTED_DB="$DATA_DIR/wechat.db"
CONFIG_FILE="$DATA_DIR/config.env"

LIMIT=20

# Parse arguments
QUERY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --limit|-n)
      LIMIT="$2"
      shift 2
      ;;
    -*)
      echo "Unknown flag: $1" >&2
      exit 1
      ;;
    *)
      QUERY="$1"
      shift
      ;;
  esac
done

if [ -z "$QUERY" ]; then
  echo "Usage: wechat \"<query>\" [--limit N]" >&2
  echo "" >&2
  echo "Examples:" >&2
  echo "  wechat \"meeting tomorrow\"  # fuzzy: matches either word" >&2
  echo "  wechat \"from:张三\"" >&2
  echo "  wechat \"type:image\"" >&2
  exit 1
fi

# Load config
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"

# Auto-init if no key or no database
if [ -z "${WECHAT_KEY:-}" ] || [ ! -f "$DECRYPTED_DB" ]; then
  echo "First run - setting up..." >&2
  "$SCRIPT_DIR/init.sh"
  # Reload config after init
  source "$CONFIG_FILE"
fi

# Check FTS index
if ! sqlite3 "$DECRYPTED_DB" "SELECT 1 FROM sqlite_master WHERE name='message_fts'" 2>/dev/null | grep -q 1; then
  echo "Rebuilding index..." >&2
  "$SCRIPT_DIR/init.sh"
fi

# Build SQL based on query syntax
if [[ "$QUERY" =~ ^from:(.+)$ ]]; then
  TALKER="${BASH_REMATCH[1]}"
  SQL="SELECT timestamp, talker, content FROM message_fts WHERE talker LIKE '%$TALKER%' ORDER BY timestamp DESC LIMIT $LIMIT"
elif [[ "$QUERY" =~ ^type:(.+)$ ]]; then
  TYPE="${BASH_REMATCH[1]}"
  case "$TYPE" in
    image|图片) TYPE_NUM=3 ;;
    voice|语音) TYPE_NUM=34 ;;
    video|视频) TYPE_NUM=43 ;;
    file|文件) TYPE_NUM=49 ;;
    *) TYPE_NUM="$TYPE" ;;
  esac
  SQL="SELECT timestamp, talker, content FROM message_fts WHERE type = $TYPE_NUM ORDER BY timestamp DESC LIMIT $LIMIT"
else
  # Fuzzy search: split into words, OR match, order by recency
  read -ra WORDS <<< "$QUERY"
  WHERE_CLAUSE=""
  for word in "${WORDS[@]}"; do
    escaped=$(echo "$word" | sed "s/'/''/g")
    [ -n "$WHERE_CLAUSE" ] && WHERE_CLAUSE="$WHERE_CLAUSE OR "
    WHERE_CLAUSE="${WHERE_CLAUSE}(content LIKE '%$escaped%' OR talker LIKE '%$escaped%')"
  done
  SQL="SELECT timestamp, talker, content FROM message_fts WHERE $WHERE_CLAUSE ORDER BY timestamp DESC LIMIT $LIMIT"
fi

# Execute and format
sqlite3 -header -column "$DECRYPTED_DB" ".width 19 15 50" "$SQL"
