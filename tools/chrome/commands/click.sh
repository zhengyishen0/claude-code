#!/bin/bash
# click.sh - Smart click using recon format
# Usage: click.sh "[text@aria](#testid)" [-S SECTION] [--times N]

if [[ "$1" == "--help" ]]; then
  echo "click, c TARGET(s) [-S SECTION] [-t N] [-d MS]  Smart click element(s)"
  echo "  TARGET: copy from recon output, e.g. \"[@Search](#btn)\""
  echo "  -S/--section: scope click to section (aria-label, heading, or tag)"
  echo "  -t/--times N: click same element N times"
  echo "  -d/--delay MS: delay between clicks in ms (default: 100)"
  echo "  Multiple targets: click \"[a]\" \"[b]\" \"[c]\" (clicks each once)"
  echo "  Also accepts CSS selectors as fallback"
  echo ""
  echo "Chain with +: click TARGET + wait + recon"
  exit 0
fi

SCRIPT_DIR="$(dirname "$0")/.."

TARGETS=()
SECTION=""
TIMES=1
DELAY=100

while [ $# -gt 0 ]; do
  case "$1" in
    --section|--S|-S)
      SECTION="$2"
      shift 2
      ;;
    --times|--t|-t)
      TIMES="$2"
      shift 2
      ;;
    --delay|--d|-d)
      DELAY="$2"
      shift 2
      ;;
    -*)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
    *)
      TARGETS+=("$1")
      shift
      ;;
  esac
done

if [ ${#TARGETS[@]} -eq 0 ]; then
  echo "Usage: click.sh \"[text@aria](#testid)\"" >&2
  echo "       click.sh \"[a]\" \"[b]\" \"[c]\"  # multiple targets" >&2
  echo "       click.sh \"[+]\" --times 5     # repeat 5 times" >&2
  exit 1
fi

# Validate: --times only with single target
if [ "$TIMES" -gt 1 ] && [ ${#TARGETS[@]} -gt 1 ]; then
  echo "Error: --times cannot be used with multiple targets" >&2
  exit 1
fi

# Build JSON array for targets
TARGETS_JSON="["
for i in "${!TARGETS[@]}"; do
  TARGET_ESC=$(printf '%s' "${TARGETS[$i]}" | sed 's/\\/\\\\/g; s/"/\\"/g')
  TARGETS_JSON+='"'"$TARGET_ESC"'"'
  if [ $i -lt $((${#TARGETS[@]} - 1)) ]; then
    TARGETS_JSON+=","
  fi
done
TARGETS_JSON+="]"

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
  # Single click or multiple targets - execute once
  result=$(chrome-cli execute 'var _p={targets:'"$TARGETS_JSON"', times:1, section:"'"$SECTION_ESC"'"}; '"$JS_CODE")
  echo "$result"
fi
