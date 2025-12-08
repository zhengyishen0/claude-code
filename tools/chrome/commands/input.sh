#!/bin/bash
# input.sh - Set input values with unified selector=value format
# Usage: input.sh "@aria=value" "#id=value" "text=value" [-c]

if [[ "$1" == "--help" ]]; then
  echo "input FIELD(s) [--clear]  Set input value(s)"
  echo ""
  echo "Format: selector=value"
  echo "  @label=value    by aria-label (e.g. @Where=Paris)"
  echo "  #id=value       by id/testid/CSS (e.g. #email=test@example.com)"
  echo "  text=value      by placeholder/aria (e.g. Where=Paris)"
  echo ""
  echo "Options:"
  echo "  --clear: clear field(s) first"
  echo ""
  echo "Examples:"
  echo "  input \"@Where=Paris\""
  echo "  input \"#email=test@example.com\" \"#password=secret\""
  echo "  input \"Where=Paris\" \"When=March\" -c"
  echo ""
  echo "Chain with +: input \"@Where=Paris\" + wait + recon"
  exit 0
fi

SCRIPT_DIR="$(dirname "$0")/.."
[ -f "$SCRIPT_DIR/config" ] && source "$SCRIPT_DIR/config"

FIELDS=()
CLEAR="false"

while [ $# -gt 0 ]; do
  case "$1" in
    --clear)
      CLEAR="true"
      shift
      ;;
    -*)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
    *)
      FIELDS+=("$1")
      shift
      ;;
  esac
done

if [ ${#FIELDS[@]} -eq 0 ]; then
  echo "Usage: input.sh \"@aria=value\" \"#id=value\" \"text=value\"" >&2
  echo "       input.sh \"@Where=Paris\" \"#date=2024-01-01\"" >&2
  exit 1
fi

# Build JSON array of fields
# Parse each field: @aria=value, #id=value, or text=value
FIELDS_JSON="["
for i in "${!FIELDS[@]}"; do
  FIELD="${FIELDS[$i]}"

  # Split on first = only
  SELECTOR="${FIELD%%=*}"
  VALUE="${FIELD#*=}"

  # Determine type from prefix
  if [[ "$SELECTOR" == @* ]]; then
    TYPE="aria"
    SELECTOR="${SELECTOR:1}"  # Remove @ prefix
  elif [[ "$SELECTOR" == \#* ]]; then
    TYPE="id"
    SELECTOR="${SELECTOR:1}"  # Remove # prefix
  else
    TYPE="text"
  fi

  # Escape for JSON
  SELECTOR_ESC=$(printf '%s' "$SELECTOR" | sed 's/\\/\\\\/g; s/"/\\"/g')
  VALUE_ESC=$(printf '%s' "$VALUE" | sed 's/\\/\\\\/g; s/"/\\"/g')

  FIELDS_JSON+='{"type":"'"$TYPE"'","selector":"'"$SELECTOR_ESC"'","value":"'"$VALUE_ESC"'"}'
  if [ $i -lt $((${#FIELDS[@]} - 1)) ]; then
    FIELDS_JSON+=","
  fi
done
FIELDS_JSON+="]"

# Read JS file
JS_CODE=$(cat "$SCRIPT_DIR/js/set-input.js")

# Execute with fields array
INPUT_DELAY=${CHROME_INPUT_DELAY:-100}
result=$(chrome-cli execute 'var _p={fields:'"$FIELDS_JSON"',clear:'"$CLEAR"',delay:'"$INPUT_DELAY"'}; '"$JS_CODE")
echo "$result"
