#!/bin/bash
#
# File watcher for IVDX vault
# - Watches vault root for new ideas → triggers new-note.sh
# - Watches active/ for submit changes → triggers submit.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
VAULT_DIR="$PROJECT_ROOT/vault"

echo "=== IVDX File Watcher ==="
echo "Watching: $VAULT_DIR"
echo "Scripts:  $SCRIPT_DIR/scripts/"
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

# Watch for file changes
fswatch -0 \
  --event Created --event Updated \
  --exclude "\.DS_Store" \
  --exclude "\.obsidian" \
  "$VAULT_DIR" | while read -d "" event; do

  # Skip non-markdown files
  if [[ ! "$event" == *.md ]]; then
    continue
  fi

  # Skip if file doesn't exist (deleted quickly)
  if [[ ! -f "$event" ]]; then
    continue
  fi

  # Skip empty files (iCloud placeholder not synced yet)
  if [[ ! -s "$event" ]]; then
    echo "$(date '+%H:%M:%S') ⏳ Waiting for sync: $(basename "$event")"
    continue
  fi

  # Determine what kind of event this is
  REL_PATH="${event#$VAULT_DIR/}"

  # Skip index.md
  if [[ "$REL_PATH" == "index.md" ]]; then
    continue
  fi

  # Skip archive
  if [[ "$REL_PATH" == archive/* ]]; then
    continue
  fi

  # New note in vault root
  if [[ "$REL_PATH" != */* ]]; then
    echo ""
    echo "$(date '+%H:%M:%S') 📥 New idea: $REL_PATH"
    echo "   Run: ./scripts/new-note.sh \"$event\""
    echo ""
    # Uncomment to auto-trigger:
    # "$SCRIPT_DIR/scripts/new-note.sh" "$event"
    continue
  fi

  # Document in active/
  if [[ "$REL_PATH" == active/* ]]; then
    # Check for submit: true
    if has_submit_true "$event"; then
      DOC_TYPE=$(grep -m1 "^type:" "$event" | sed 's/type: *//' || echo "unknown")

      # Special case: contract needs to be signed, not just submitted
      if [[ "$DOC_TYPE" == "contract" ]] && ! is_contract_signed "$event"; then
        continue
      fi

      echo ""
      echo "$(date '+%H:%M:%S') ✅ Submitted: $REL_PATH ($DOC_TYPE)"
      echo "   Run: ./scripts/submit.sh \"$event\""
      echo ""
      # Uncomment to auto-trigger:
      # "$SCRIPT_DIR/scripts/submit.sh" "$event"
    fi
    continue
  fi

done
