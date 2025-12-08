#!/bin/bash
# click.sh - Smart click using recon format
# Usage: click.sh "[text@aria](#testid)" [--times N]

if [[ "$1" == "--help" ]]; then
  echo "click TARGET [--times N] [--delay MS]  Smart click element"
  echo "  TARGET: copy from recon output, e.g. \"[@Search](#btn)\""
  echo "  --times N: click same element N times"
  echo "  --delay MS: delay between clicks in ms (default: 100)"
  echo "  Also accepts CSS selectors as fallback"
  echo ""
  echo "Auto-mode (CHROME_AUTO_MODE=true, default):"
  echo "  Automatically detects context and runs wait+recon:"
  echo "  - Navigation: waits for page load, recons full page"
  echo "  - Modal open: waits for dialog, recons dialog section only"
  echo "  - Modal close: waits for dialog gone, recons main content"
  echo "  - Inline update: waits for DOM change, recons full page"
  echo ""
  echo "Manual mode (export CHROME_AUTO_MODE=false):"
  echo "  Chain with +: click TARGET + wait + recon"
  echo "  Multiple clicks: click \"[a]\" + click \"[b]\" + click \"[c]\""
  exit 0
fi

SCRIPT_DIR="$(dirname "$0")/.."
[ -f "$SCRIPT_DIR/config" ] && source "$SCRIPT_DIR/config"

TARGET=""
TIMES=1
DELAY=${CHROME_CLICK_DELAY:-100}
AUTO_MODE=${CHROME_AUTO_MODE:-true}

while [ $# -gt 0 ]; do
  case "$1" in
    --times)
      TIMES="$2"
      shift 2
      ;;
    --delay)
      DELAY="$2"
      shift 2
      ;;
    -*)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
    *)
      if [ -n "$TARGET" ]; then
        echo "Error: Multiple targets not supported. Use chaining instead:" >&2
        echo "  click \"[a]\" + click \"[b]\" + click \"[c]\"" >&2
        exit 1
      fi
      TARGET="$1"
      shift
      ;;
  esac
done

if [ -z "$TARGET" ]; then
  echo "Usage: click.sh \"[text@aria](#testid)\"" >&2
  echo "       click.sh \"[+]\" --times 5" >&2
  echo "  For multiple clicks, use chaining: click \"[a]\" + click \"[b]\"" >&2
  exit 1
fi

# Build single-element JSON array
TARGET_ESC=$(printf '%s' "$TARGET" | sed 's/\\/\\\\/g; s/"/\\"/g')
TARGETS_JSON='["'"$TARGET_ESC"'"]'

# Read JS file
JS_CODE=$(cat "$SCRIPT_DIR/js/click-element.js")

# Execute click (with or without --times)
result=$(chrome-cli execute 'var _p={targets:'"$TARGETS_JSON"', times:'"$TIMES"'}; '"$JS_CODE")

# Check for failure
if [[ "$result" == FAIL* ]]; then
  echo "$result"
  exit 1
fi

# Parse result: OK:...|contextType|waitSelector|waitGone|reconFilter
IFS='|' read -r status contextType waitSelector waitGone reconFilter <<< "$result"

# Always echo the click result (without context info)
echo "$status"

# Auto-wait and auto-recon if enabled
if [ "$AUTO_MODE" = "true" ]; then
  case "$contextType" in
    navigation)
      # Navigation: small delay then full recon
      sleep 0.3
      "$SCRIPT_DIR/commands/recon.sh"
      ;;
    modal-open)
      # Modal opened: wait for dialog, then recon dialog section
      "$SCRIPT_DIR/commands/wait.sh" "$waitSelector" 2>/dev/null || true
      "$SCRIPT_DIR/commands/recon.sh" | eval "$reconFilter" 2>/dev/null || "$SCRIPT_DIR/commands/recon.sh"
      ;;
    modal-close)
      # Modal closed: wait for dialog to disappear, then recon main
      "$SCRIPT_DIR/commands/wait.sh" "$waitSelector" --gone 2>/dev/null || true
      "$SCRIPT_DIR/commands/recon.sh" | eval "$reconFilter" 2>/dev/null || "$SCRIPT_DIR/commands/recon.sh"
      ;;
    inline)
      # Inline update: generic wait, full recon
      "$SCRIPT_DIR/commands/wait.sh" 2>/dev/null || true
      "$SCRIPT_DIR/commands/recon.sh"
      ;;
    *)
      # Unknown context: just do generic wait and recon
      "$SCRIPT_DIR/commands/wait.sh" 2>/dev/null || true
      "$SCRIPT_DIR/commands/recon.sh"
      ;;
  esac
fi
