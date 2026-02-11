#!/bin/bash
#
# File watcher for IVDX vault
# - Watches vault root for new ideas → triggers new-note.sh
# - Watches active/ for submit changes → triggers submit.sh
#
# Logic:
# - Title (filename) IS the idea - content optional
# - 15s debounce - waits for user to stop typing
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
# Resolve symlink to real path (fswatch returns real paths)
VAULT_DIR="$(cd "$PROJECT_ROOT/vault" && pwd -P)"
DEBOUNCE_SEC=15
PENDING_DIR=$(mktemp -d)

trap "rm -rf $PENDING_DIR" EXIT

echo "=== IVDX File Watcher ==="
echo "Watching: $VAULT_DIR"
echo "Debounce: ${DEBOUNCE_SEC}s"
echo "Press Ctrl+C to stop"
echo ""

# Function to check if file has submit: true
has_submit_true() {
    grep -q "^submit: true" "$1" 2>/dev/null
}

# Function to check if contract is signed
is_contract_signed() {
    grep -q "^status: signed" "$1" 2>/dev/null
}

# Function to get hash of filepath for temp file naming
file_hash() {
    echo "$1" | md5 | cut -c1-16
}

# Background job to check for debounced files
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

                # New note in vault root (no subdirectory)
                if [[ "$REL_PATH" != */* ]]; then
                    echo ""
                    echo "$(date '+%H:%M:%S') 🚀 Processing: $REL_PATH"
                    "$SCRIPT_DIR/scripts/new-note.sh" "$ORIGINAL_PATH" || true
                    continue
                fi

                # Submit in active/
                if [[ "$REL_PATH" == active/* ]] && has_submit_true "$ORIGINAL_PATH"; then
                    DOC_TYPE=$(grep -m1 "^type:" "$ORIGINAL_PATH" | sed 's/type: *//' || echo "unknown")
                    if [[ "$DOC_TYPE" != "contract" ]] || is_contract_signed "$ORIGINAL_PATH"; then
                        echo ""
                        echo "$(date '+%H:%M:%S') 🚀 Processing submit: $REL_PATH"
                        "$SCRIPT_DIR/scripts/submit.sh" "$ORIGINAL_PATH" || true
                    fi
                fi
            fi
        done
    done
) &

# Watch for file changes
fswatch -0 \
  --event Created --event Updated \
  --exclude "\.DS_Store" \
  --exclude "\.obsidian" \
  "$VAULT_DIR" | while read -d "" event; do

  # Skip non-markdown files
  [[ "$event" == *.md ]] || continue

  # Skip if file doesn't exist
  [[ -f "$event" ]] || continue

  REL_PATH="${event#$VAULT_DIR/}"

  # Skip index.md and archive
  [[ "$REL_PATH" == "index.md" ]] && continue
  [[ "$REL_PATH" == archive/* ]] && continue

  # Create/update pending file
  HASH=$(file_hash "$event")
  PENDING_FILE="$PENDING_DIR/$HASH"

  if [[ ! -f "$PENDING_FILE" ]]; then
    echo "$(date '+%H:%M:%S') 📥 Detected: $REL_PATH (waiting ${DEBOUNCE_SEC}s...)"
  else
    echo "$(date '+%H:%M:%S') ✏️  Updated: $REL_PATH (resetting timer...)"
  fi

  echo "$event" > "$PENDING_FILE"

done
