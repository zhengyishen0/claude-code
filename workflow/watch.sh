#!/bin/bash
#
# File watcher for IVDX vault
# - Watches vault root for new ideas → triggers new-note.sh
# - Watches vault/tasks/*.md for submit: true → triggers submit.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
VAULT_DIR="$(cd "$PROJECT_ROOT/vault" && pwd -P)"
DEBOUNCE_SEC=15
PENDING_DIR=$(mktemp -d)

trap "rm -rf $PENDING_DIR" EXIT

echo "=== IVDX File Watcher ==="
echo "Watching: $VAULT_DIR"
echo "Debounce: ${DEBOUNCE_SEC}s"
echo "Press Ctrl+C to stop"
echo ""

has_submit_true() {
    grep -q "^submit: true" "$1" 2>/dev/null
}

file_hash() {
    echo "$1" | md5 | cut -c1-16
}

# Background checker
(
    while true; do
        sleep 2
        NOW=$(date +%s)

        for pending_file in "$PENDING_DIR"/*; do
            [[ -f "$pending_file" ]] || continue

            ORIGINAL_PATH=$(cat "$pending_file")
            LAST_SEEN=$(stat -f %m "$pending_file")
            ELAPSED=$((NOW - LAST_SEEN))

            if [[ $ELAPSED -ge $DEBOUNCE_SEC ]]; then
                rm "$pending_file"
                [[ -f "$ORIGINAL_PATH" ]] || continue

                REL_PATH="${ORIGINAL_PATH#$VAULT_DIR/}"

                # New note in vault root
                if [[ "$REL_PATH" != */* ]]; then
                    echo ""
                    echo "$(date '+%H:%M:%S') 🚀 Processing: $REL_PATH"
                    "$SCRIPT_DIR/scripts/new-note.sh" "$ORIGINAL_PATH" || true
                    continue
                fi

                # Submit: tasks/*.md with submit: true
                if [[ "$REL_PATH" == tasks/*.md ]] && has_submit_true "$ORIGINAL_PATH"; then
                    echo ""
                    echo "$(date '+%H:%M:%S') 🚀 Processing submit: $REL_PATH"
                    "$SCRIPT_DIR/scripts/submit.sh" "$ORIGINAL_PATH" || true
                fi
            fi
        done
    done
) &

# Watch for changes
fswatch -0 \
  --event Created --event Updated --event AttributeModified --event Renamed \
  --exclude "\.DS_Store" \
  --exclude "\.obsidian" \
  --exclude "/resources/" \
  "$VAULT_DIR" | while read -d "" event; do

  [[ "$event" == *.md ]] || continue
  [[ -f "$event" ]] || continue

  REL_PATH="${event#$VAULT_DIR/}"

  # Skip index, archive, journal
  [[ "$REL_PATH" == "index.md" ]] && continue
  [[ "$REL_PATH" == archive/* ]] && continue
  [[ "$REL_PATH" == journal/* ]] && continue

  HASH=$(file_hash "$event")
  PENDING_FILE="$PENDING_DIR/$HASH"

  if [[ ! -f "$PENDING_FILE" ]]; then
    echo "$(date '+%H:%M:%S') 📥 Detected: $REL_PATH (waiting ${DEBOUNCE_SEC}s...)"
  else
    echo "$(date '+%H:%M:%S') ✏️  Updated: $REL_PATH (resetting timer...)"
  fi

  echo "$event" > "$PENDING_FILE"

done
