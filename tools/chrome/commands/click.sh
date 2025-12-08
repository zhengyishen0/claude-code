#!/bin/bash
# click.sh - Smart click using recon format
# Usage: click.sh "[text@aria](#testid)" [-S SECTION] [--times N]

if [[ "$1" == "--help" ]]; then
  echo "click TARGET [--section SECTION] [--times N] [--delay MS]  Smart click element"
  echo "  TARGET: copy from recon output, e.g. \"[@Search](#btn)\""
  echo "  --section: scope click to section (aria-label, heading, or tag)"
  echo "  --times N: click same element N times"
  echo "  --delay MS: delay between clicks in ms (default: 100)"
  echo "  Also accepts CSS selectors as fallback"
  echo ""
  echo "Chain with +: click TARGET + wait + recon"
  echo "  Multiple clicks: click \"[a]\" + click \"[b]\" + click \"[c]\""
  exit 0
fi

SCRIPT_DIR="$(dirname "$0")/.."

TARGET=""
SECTION=""
TIMES=1
DELAY=100

while [ $# -gt 0 ]; do
  case "$1" in
    --section)
      SECTION="$2"
      shift 2
      ;;
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

SECTION_ESC=$(printf '%s' "$SECTION" | sed 's/"/\\"/g')

# Read JS file
JS_CODE=$(cat "$SCRIPT_DIR/js/click-element.js")

# For --times with React components, execute separate chrome-cli calls with shell delays
# This allows React to process state updates between clicks
# Minimum 50ms delay for safety across different sites
if [ "$TIMES" -gt 1 ]; then
  if [ "$DELAY" -lt 50 ]; then
    DELAY=50
  fi
  DELAY_SEC=$(echo "scale=3; $DELAY / 1000" | bc)
  for ((i=1; i<=TIMES; i++)); do
    result=$(chrome-cli execute 'var _p={targets:'"$TARGETS_JSON"', times:1, section:"'"$SECTION_ESC"'"}; '"$JS_CODE")
    if [[ "$result" == FAIL* ]]; then
      echo "FAIL:click $i of $TIMES failed - $result"
      exit 1
    fi
    if [ $i -lt $TIMES ]; then
      sleep "$DELAY_SEC"
    fi
  done
  echo "OK:clicked $TIMES times"
else
  # Single click
  result=$(chrome-cli execute 'var _p={targets:'"$TARGETS_JSON"', times:1, section:"'"$SECTION_ESC"'"}; '"$JS_CODE")
  echo "$result"
fi
