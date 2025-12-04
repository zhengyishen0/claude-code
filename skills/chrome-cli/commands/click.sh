#!/bin/bash
# click.sh - Smart click using recon format
# Usage: click.sh "[text@aria](#testid)" [--wait] [--section|-S SECTION]
#        click.sh "[@Search](#search-btn)"
#        click.sh "[Filters](#filter-btn)"
#        click.sh "[@Close](#button)" -S "Provide feedback"
#        click.sh "button.submit"  (CSS selector fallback)

SCRIPT_DIR="$(dirname "$0")/.."

TARGET=""
WAIT=""
SECTION=""

while [ $# -gt 0 ]; do
  case "$1" in
    --wait|-w)
      WAIT="true"
      shift
      ;;
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

# If --wait, poll for DOM change
if [ "$WAIT" = "true" ]; then
  SNAPSHOT=$(chrome-cli execute "document.body.innerHTML.length + '|' + document.querySelectorAll('*').length")
  TIMEOUT=5
  elapsed=0
  interval=0.3
  while (( $(echo "$elapsed < $TIMEOUT" | bc -l) )); do
    sleep $interval
    elapsed=$(echo "$elapsed + $interval" | bc)
    CURRENT=$(chrome-cli execute "document.body.innerHTML.length + '|' + document.querySelectorAll('*').length")
    if [ "$CURRENT" != "$SNAPSHOT" ]; then
      break
    fi
  done
fi
