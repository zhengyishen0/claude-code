#!/bin/bash
# Initialize WeChat database - pull from emulator and decrypt
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$SCRIPT_DIR/data"
CONFIG_FILE="$DATA_DIR/config.env"

WECHAT_DB_PATH="/data/data/com.tencent.mm/MicroMsg"
ENCRYPTED_DB="$DATA_DIR/EnMicroMsg.db"
DECRYPTED_DB="$DATA_DIR/wechat.db"

mkdir -p "$DATA_DIR"

# Load config if exists
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"

# Check dependencies
check_deps() {
  local missing=""
  command -v adb >/dev/null || missing="$missing adb"
  command -v sqlcipher >/dev/null || missing="$missing sqlcipher"

  if [ -n "$missing" ]; then
    echo "Missing:$missing" >&2
    echo "Install: brew install android-platform-tools sqlcipher" >&2
    exit 1
  fi
}

# Find WeChat database on emulator
find_wechat_db() {
  echo "Finding WeChat database..." >&2

  if ! adb devices 2>/dev/null | grep -q "device$"; then
    echo "Error: No Android device/emulator connected" >&2
    exit 1
  fi

  # Find user's uin directory (MD5 hash)
  local uin_dir=$(adb shell "ls -1 $WECHAT_DB_PATH 2>/dev/null | grep -v '^$' | head -1" 2>/dev/null | tr -d '\r\n')

  if [ -z "$uin_dir" ]; then
    echo "Error: WeChat data not found. Is WeChat installed?" >&2
    exit 1
  fi

  echo "$WECHAT_DB_PATH/$uin_dir/EnMicroMsg.db"
}

# Pull database from emulator
pull_database() {
  local db_path="$1"
  echo "Pulling database..." >&2

  adb root >/dev/null 2>&1 || true
  sleep 1

  if ! adb pull "$db_path" "$ENCRYPTED_DB" 2>/dev/null; then
    echo "Trying with su..." >&2
    adb shell "su -c 'cp $db_path /data/local/tmp/EnMicroMsg.db'" 2>/dev/null
    adb pull /data/local/tmp/EnMicroMsg.db "$ENCRYPTED_DB"
    adb shell "rm /data/local/tmp/EnMicroMsg.db" 2>/dev/null || true
  fi

  echo "Pulled: $(ls -lh "$ENCRYPTED_DB" | awk '{print $5}')" >&2
}

# Decrypt database
decrypt_database() {
  if [ -z "${WECHAT_KEY:-}" ]; then
    echo "Error: WECHAT_KEY not set" >&2
    echo "Run: wechat init <key>" >&2
    echo "" >&2
    echo "To find key, use Frida:" >&2
    echo "  frida -U -f com.tencent.mm -l find_key.js" >&2
    exit 1
  fi

  echo "Decrypting..." >&2
  rm -f "$DECRYPTED_DB"

  sqlcipher "$ENCRYPTED_DB" << EOF
PRAGMA key = '$WECHAT_KEY';
PRAGMA cipher_compatibility = 1;
ATTACH DATABASE '$DECRYPTED_DB' AS plaintext KEY '';
SELECT sqlcipher_export('plaintext');
DETACH DATABASE plaintext;
EOF

  if [ ! -f "$DECRYPTED_DB" ]; then
    echo "Error: Decryption failed" >&2
    exit 1
  fi

  echo "Decrypted: $(ls -lh "$DECRYPTED_DB" | awk '{print $5}')" >&2
}

# Build FTS5 index
build_search_index() {
  echo "Building search index..." >&2

  sqlite3 "$DECRYPTED_DB" << 'EOF'
DROP TABLE IF EXISTS message_fts;
CREATE VIRTUAL TABLE message_fts USING fts5(
  msgId,
  talker,
  content,
  timestamp,
  type,
  tokenize='unicode61'
);

INSERT INTO message_fts (msgId, talker, content, timestamp, type)
SELECT
  m.msgId,
  COALESCE(cr.displayname, c.conRemark, c.nickname, m.talker) as talker,
  CASE
    WHEN m.type = 1 THEN m.content
    WHEN m.type = 3 THEN '[图片]'
    WHEN m.type = 34 THEN COALESCE(v.content, '[语音]')
    WHEN m.type = 43 THEN '[视频]'
    WHEN m.type = 47 THEN '[表情]'
    WHEN m.type = 49 THEN
      CASE
        WHEN m.content LIKE '%<type>6</type>%' THEN '[文件]'
        WHEN m.content LIKE '%<type>5</type>%' THEN '[链接] ' || COALESCE(
          substr(m.content, instr(m.content, '<title>') + 7,
            instr(m.content, '</title>') - instr(m.content, '<title>') - 7), '')
        ELSE '[分享]'
      END
    WHEN m.type = 10000 THEN '[系统]'
    ELSE m.content
  END as content,
  datetime(m.createTime/1000, 'unixepoch', 'localtime') as timestamp,
  m.type
FROM message m
LEFT JOIN rcontact c ON m.talker = c.username
LEFT JOIN chatroom cr ON m.talker = cr.chatroomname
LEFT JOIN VoiceTransText v ON m.msgId = v.msgId
WHERE m.content IS NOT NULL AND m.content != '';

SELECT 'Indexed ' || count(*) || ' messages' FROM message_fts;
EOF
}

# Main
main() {
  check_deps

  # Save key if provided
  if [ -n "${1:-}" ]; then
    export WECHAT_KEY="$1"
    echo "WECHAT_KEY='$1'" > "$CONFIG_FILE"
    echo "Key saved" >&2
  fi

  local db_path
  if [ -n "${WECHAT_DB_FULL_PATH:-}" ]; then
    db_path="$WECHAT_DB_FULL_PATH"
  else
    db_path=$(find_wechat_db)
    echo "WECHAT_DB_FULL_PATH='$db_path'" >> "$CONFIG_FILE" 2>/dev/null || true
  fi

  pull_database "$db_path"
  decrypt_database
  build_search_index

  echo "Done. Run: wechat search \"query\"" >&2
}

main "$@"
