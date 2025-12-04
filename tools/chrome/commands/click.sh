#!/bin/bash
# click.sh - Smart click using recon format
# Usage: click.sh "[text@aria](#testid)" [-S SECTION]

if [[ "$1" == "--help" ]]; then
  echo "click, c TARGET [-S SECTION]  Smart click element"
  echo "  TARGET: copy from recon output, e.g. \"[@Search](#btn)\""
  echo "  -S/--section: scope click to section (aria-label, heading, or tag)"
  echo "  Also accepts CSS selectors as fallback"
  echo ""
  echo "Chain with +: click TARGET + wait + recon"
  exit 0
fi

SCRIPT_DIR="$(dirname "$0")/.."

TARGET=""
SECTION=""

while [ $# -gt 0 ]; do
  case "$1" in
    --section|-S)
      SECTION="$2"
      shift 2
      ;;
    -*)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
    *)
      TARGET="$1"
      shift
      ;;
  esac
done

if [ -z "$TARGET" ]; then
  echo "Usage: click.sh \"[text@aria](#testid)\"" >&2
  echo "       click.sh \"[@aria](#testid)\"" >&2
  echo "       click.sh \"[text](#button)\"" >&2
  exit 1
fi

# Escape double quotes for JS
TARGET_ESC=$(printf '%s' "$TARGET" | sed 's/"/\\"/g')
SECTION_ESC=$(printf '%s' "$SECTION" | sed 's/"/\\"/g')

# Read JS file
JS_CODE=$(cat "$SCRIPT_DIR/js/click-element.js")

# Execute - JS will auto-detect if it's recon format or CSS selector
result=$(chrome-cli execute 'var _p={auto:"'"$TARGET_ESC"'", section:"'"$SECTION_ESC"'"}; '"$JS_CODE")
echo "$result"
