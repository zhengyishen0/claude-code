#!/bin/bash
# input.sh - Set input value with multiple selector strategies
# Usage: input.sh "CSS_SELECTOR" "VALUE" [--clear]

if [[ "$1" == "--help" ]]; then
  echo "input, i SEL VAL [--clear]  Set input value"
  echo "  input \"#email\" \"test@example.com\""
  echo "  input --aria LABEL VAL    by aria-label"
  echo "  input --text PLACEHOLDER VAL  by placeholder"
  echo "  input --testid ID VAL     by data-testid"
  echo "  --clear/-c: clear field first"
  echo ""
  echo "Chain with +: input --aria Search tokyo + wait + recon Form"
  exit 0
fi

SCRIPT_DIR="$(dirname "$0")/.."

SELECTOR=""
TEXT=""
ARIA=""
TESTID=""
VALUE=""
CLEAR="false"

while [ $# -gt 0 ]; do
  case "$1" in
    --text|-t)
      TEXT="$2"
      shift 2
      ;;
    --aria|-a)
      ARIA="$2"
      shift 2
      ;;
    --testid|-d)
      TESTID="$2"
      shift 2
      ;;
    --clear|-c)
      CLEAR="true"
      shift
      ;;
    -*)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
    *)
      # First positional is selector (if no --flag), second is value
      if [ -z "$SELECTOR" ] && [ -z "$TEXT" ] && [ -z "$ARIA" ] && [ -z "$TESTID" ]; then
        SELECTOR="$1"
      else
        VALUE="$1"
      fi
      shift
      ;;
  esac
done

if [ -z "$VALUE" ]; then
  echo "Usage: input.sh \"SELECTOR\" \"VALUE\" [--clear]" >&2
  echo "       input.sh --aria \"label\" \"VALUE\" [--clear]" >&2
  exit 1
fi

# Escape double quotes in values for JS string literals
SELECTOR_ESC=$(printf '%s' "$SELECTOR" | sed 's/"/\\"/g')
TEXT_ESC=$(printf '%s' "$TEXT" | sed 's/"/\\"/g')
ARIA_ESC=$(printf '%s' "$ARIA" | sed 's/"/\\"/g')
TESTID_ESC=$(printf '%s' "$TESTID" | sed 's/"/\\"/g')
VALUE_ESC=$(printf '%s' "$VALUE" | sed 's/"/\\"/g')

# Read JS file
JS_CODE=$(cat "$SCRIPT_DIR/js/set-input.js")

# Execute with _p variable
result=$(chrome-cli execute 'var _p={selector:"'"$SELECTOR_ESC"'",text:"'"$TEXT_ESC"'",aria:"'"$ARIA_ESC"'",testid:"'"$TESTID_ESC"'",value:"'"$VALUE_ESC"'",clear:'"$CLEAR"'}; '"$JS_CODE")
echo "$result"
