#!/bin/bash
# Search Claude sessions
# Syntax: memory search "OR terms" [--require "required terms"] [--exclude "excluded terms"] [--recall "question"]
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SESSION_DIR="$HOME/.claude/projects"
INDEX_FILE="$HOME/.claude/memory-index.tsv"

# Parse args
SESSIONS=5    # Default: 5 sessions
MESSAGES=5    # Default: 5 messages per session
CONTEXT=300   # Default: 300 chars per snippet
QUERY=""
RECALL_QUESTION=""
OR_QUERY=""
REQUIRE_QUERY=""
EXCLUDE_QUERY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sessions)
      SESSIONS="$2"
      shift 2
      ;;
    --messages)
      MESSAGES="$2"
      shift 2
      ;;
    --context)
      CONTEXT="$2"
      shift 2
      ;;
    --require)
      REQUIRE_QUERY="$2"
      shift 2
      ;;
    --exclude)
      EXCLUDE_QUERY="$2"
      shift 2
      ;;
    --recall|-r)
      RECALL_QUESTION="$2"
      shift 2
      ;;
    -*)
      echo "Error: Unknown flag '$1'" >&2
      exit 1
      ;;
    *)
      QUERY="$1"
      shift
      ;;
  esac
done

# Validation: query is required
if [ -z "$QUERY" ]; then
  echo "Error: Missing query (first argument)" >&2
  echo "" >&2
  echo "Usage: memory search QUERY [--require TERMS] [--exclude TERMS] [--recall QUESTION]" >&2
  echo "" >&2
  echo "Query Modes:" >&2
  echo "  Simple mode (default): Space-separated OR terms, use --require for AND, --exclude for NOT" >&2
  echo "    Example: memory search \"chrome playwright\" --require \"click\"" >&2
  echo "    (Finds messages about chrome OR playwright that also mention click)" >&2
  echo "" >&2
  echo "  Boolean mode: Use parentheses for complex AND/OR/NOT logic" >&2
  echo "    Example: memory search \"(chrome AND click) OR (playwright AND input)\"" >&2
  echo "    Example: memory search \"((A AND B) OR (C AND D)) | not\"" >&2
  echo "    (Use | not for negation, e.g. '(A AND B) | not' to negate the expression)" >&2
  echo "" >&2
  echo "Examples:" >&2
  echo "  memory search \"asus laptop\" --require \"spec\"" >&2
  echo "  memory search \"chrome playwright\" --require \"click\" --recall \"How to fix click issues?\"" >&2
  echo "  memory search \"(chrome AND click) OR (playwright AND input)\"" >&2
  exit 1
fi

OR_QUERY="$QUERY"

[ ! -d "$SESSION_DIR" ] && { echo "Error: No Claude sessions found" >&2; exit 1; }

# Build full index with jq
# Index format: session_id \t timestamp \t type \t text \t project_path
build_full_index() {
  echo "Building index..." >&2
  # First, find all JSONL files and filter out fork sessions (those starting with queue-operation)
  find "$SESSION_DIR" -name "*.jsonl" -type f 2>/dev/null | while read -r file; do
    # Check if file starts with queue-operation (fork session)
    if ! head -1 "$file" | jq -e 'select(.type == "queue-operation")' >/dev/null 2>&1; then
      echo "$file"
    fi
  done | xargs -I{} rg -N --json '"type":"(user|assistant)"' {} 2>/dev/null | \
    jq -r '
      select(.type == "match") |
      .data.path.text as $filepath |
      .data.lines.text | fromjson |
      select(.type == "user" or .type == "assistant") |
      (.message.content |
        if type == "array" then
          [.[] | select(.type == "text") | .text] | join(" ")
        elif type == "string" then .
        else "" end
      ) as $text |
      select($text | length > 10) |
      select($text | test("<ide_|\\[Request interrupted|New environment|API Error|Limit reached|Caveat:|<bash-|<function_calls|<invoke|</invoke|<parameter|</parameter|</function_calls") | not) |
      # Filter out messages containing recall output patterns (session summaries with "[N/M] sessionid • date" format)
      select($text | test("^\\[[0-9]+/[0-9]+\\]\\s+[a-f0-9]{7}\\s+•") | not) |
      # Use filename (without path) as session ID - this naturally deduplicates compacted sessions
      ($filepath | split("/") | last | split(".jsonl") | first) as $session_id |
      [$session_id, .timestamp, .type, $text, .cwd // "unknown"] | @tsv
    ' 2>/dev/null > "$INDEX_FILE"
  echo "Index built: $(wc -l < "$INDEX_FILE" | tr -d ' ') messages" >&2
}

# Incremental update - process only new files
update_index() {
  local new_files="$1"
  # Filter out fork sessions before processing
  local non_fork_files=$(echo "$new_files" | while read -r file; do
    if [ -f "$file" ] && ! head -1 "$file" | jq -e 'select(.type == "queue-operation")' >/dev/null 2>&1; then
      echo "$file"
    fi
  done)

  if [ -z "$non_fork_files" ]; then
    echo "No new non-fork files to index" >&2
    return
  fi

  local count=$(echo "$non_fork_files" | wc -l | tr -d ' ')
  echo "Updating index ($count files)..." >&2
  echo "$non_fork_files" | xargs -I{} rg -N --json '"type":"(user|assistant)"' {} 2>/dev/null | \
    jq -r '
      select(.type == "match") |
      .data.path.text as $filepath |
      .data.lines.text | fromjson |
      select(.type == "user" or .type == "assistant") |
      (.message.content |
        if type == "array" then
          [.[] | select(.type == "text") | .text] | join(" ")
        elif type == "string" then .
        else "" end
      ) as $text |
      select($text | length > 10) |
      select($text | test("<ide_|\\[Request interrupted|New environment|API Error|Limit reached|Caveat:|<bash-|<function_calls|<invoke|</invoke|<parameter|</parameter|</function_calls") | not) |
      # Filter out messages containing recall output patterns (session summaries with "[N/M] sessionid • date" format)
      select($text | test("^\\[[0-9]+/[0-9]+\\]\\s+[a-f0-9]{7}\\s+•") | not) |
      # Use filename (without path) as session ID - this naturally deduplicates compacted sessions
      ($filepath | split("/") | last | split(".jsonl") | first) as $session_id |
      [$session_id, .timestamp, .type, $text, .cwd // "unknown"] | @tsv
    ' 2>/dev/null >> "$INDEX_FILE" || true
}

# Check if index needs update
TIMING_START=$(date +%s.%N)
if [ ! -f "$INDEX_FILE" ]; then
  build_full_index
else
  NEW_FILES=$(find "$SESSION_DIR" -name "*.jsonl" -newer "$INDEX_FILE" 2>/dev/null || true)
  if [ -n "$NEW_FILES" ]; then
    update_index "$NEW_FILES"
  fi
fi
TIMING_INDEX=$(date +%s.%N)
echo "[TIMING] Index check: $(echo "$TIMING_INDEX - $TIMING_START" | bc)s" >&2

# Convert underscore phrases to regex: "Tesla_Model_3" -> "Tesla.Model.3"
to_pattern() {
  echo "$1" | sed 's/_/./g'
}

# Check if query contains parentheses (indicates jq boolean mode)
has_parentheses() {
  [[ "$1" =~ \( || "$1" =~ \) ]]
}

# Search with jq boolean mode (for queries with parentheses)
# Uses native jq boolean operators (and, or, not) within parenthesized expressions
# Example: "(chrome AND click)" or "((chrome AND click) OR (playwright AND input))"
run_search_jq_mode() {
  local query="$1"

  # Normalize operators: convert AND/OR/NOT (case-insensitive) to jq operators
  # AND -> and, OR -> or, NOT prefix is handled in Python conversion
  query=$(echo "$query" | sed -E 's/\s+and\s+/ AND /gi; s/\s+or\s+/ OR /gi; s/\s+not\s+/ NOT /gi')

  # Get all terms from the query for ripgrep initial filter
  # Extract words that aren't operators or parentheses
  local all_terms=$(echo "$query" | grep -oE '\b[a-zA-Z_][a-zA-Z0-9_]*\b' | grep -v -i '^and$\|^or$\|^not$' | sort -u | tr '\n' '|' | sed 's/|$//')

  # If no terms found, return empty
  if [ -z "$all_terms" ]; then
    return
  fi

  # Build jq filter by converting terms to test() calls
  # Strategy: replace each term with (.data.lines.text | test("term"; "i"))
  local jq_filter="$query"

  # Replace each non-operator word with jq test() call
  # This is a simple approach: find words and wrap them
  # We'll use a helper approach: pass through to jq with regex substitution

  # For simplicity, we'll use jq's built-in string operations
  # Convert query to jq by:
  # 1. Wrap terms in test() calls
  # 2. Keep operators and parentheses as-is

  # Use Python for more reliable regex substitution
  local jq_filter=$(python3 -c "
import re

query = '''$query'''

# Replace terms with jq test() calls
def replace_terms(query):
  result = []
  tokens = []

  # Tokenize: split on spaces but preserve parentheses and pipes
  for match in re.finditer(r'\(|\)|\|[^|]|[^()\s|]+', query):
    token = match.group(0).strip()
    if token:
      tokens.append(token)

  for word in tokens:
    if word in ('(', ')'):
      result.append(word)
    elif word == '|':
      result.append(' | ')
    elif word.lower() == 'and':
      result.append(' and ')
    elif word.lower() == 'or':
      result.append(' or ')
    elif word.lower() == 'not':
      # NOT is a postfix in jq - output as-is
      # Users should write: (expr | not) for proper NOT filtering
      result.append('not ')
    else:
      # It's a term - wrap it
      pattern = word.replace('_', '.')
      result.append(f'(.data.lines.text | test(\"{pattern}\"; \"i\"))')

  return ''.join(result)

print(replace_terms(query))
")

  # Use ripgrep for initial filter, then jq for boolean logic
  rg --json -i "$all_terms" "$INDEX_FILE" 2>/dev/null | \
    jq -r "select(.type==\"match\") | select($jq_filter) | .data.lines.text" || true
}

# Search: space-separated terms become OR, then REQUIRE/EXCLUDE filters
# If query contains parentheses, use jq boolean mode
run_search() {
  # Check if main query contains parentheses
  if has_parentheses "$OR_QUERY"; then
    # Use jq boolean mode
    run_search_jq_mode "$OR_QUERY"
    return
  fi

  read -ra OR_TERMS <<< "$OR_QUERY"
  read -ra REQUIRE_TERMS <<< "$REQUIRE_QUERY"
  read -ra EXCLUDE_TERMS <<< "$EXCLUDE_QUERY"

  # Build OR pattern from first arg terms
  OR_PATTERNS=()
  for term in "${OR_TERMS[@]}"; do
    OR_PATTERNS+=("$(to_pattern "$term")")
  done
  OR_PATTERN=$(IFS='|'; echo "${OR_PATTERNS[*]}")
  [[ "$OR_PATTERN" == *"|"* ]] && OR_PATTERN="($OR_PATTERN)"

  # Build search pipeline: OR first, then REQUIRE filters (each term must match), then EXCLUDE filters
  CMD="rg -i '$OR_PATTERN' '$INDEX_FILE'"

  # Each required term creates its own filter (AND logic)
  for term in "${REQUIRE_TERMS[@]}"; do
    pattern=$(to_pattern "$term")
    CMD="$CMD | rg -i '$pattern'"
  done

  # Each excluded term creates its own filter
  for term in "${EXCLUDE_TERMS[@]}"; do
    pattern=$(to_pattern "$term")
    CMD="$CMD | grep -iv '$pattern'"
  done

  eval "$CMD" 2>/dev/null || true
}

# Execute search
TIMING_SEARCH_START=$(date +%s.%N)
RESULTS=$(run_search | sort -u || true)

TIMING_SEARCH_END=$(date +%s.%N)
echo "[TIMING] Search + filter: $(echo "$TIMING_SEARCH_END - $TIMING_SEARCH_START" | bc)s" >&2

# Post-process: Exclude messages at/before recall outputs
if [ -n "$RESULTS" ]; then
  # Find query sessions (messages indicating memory search/recall usage)
  # Look for patterns like "I'll search memory", "memory search", "Did you remember"
  # Format: session_id \t timestamp \t type \t text
  RECALL_CUTOFFS=$(echo "$RESULTS" | awk -F'\t' '$4 ~ /(I'\''ll search|memory search|Did you remember.*talked about|go back to a memory|memory recall)/ {print $1 "\t" $2}' | sort -u || true)

  if [ -n "$RECALL_CUTOFFS" ]; then
    # Build exclusion filter: for each session with recall, exclude messages at/before that timestamp
    FILTERED_RESULTS=""
    while IFS= read -r line; do
      SESSION=$(echo "$line" | cut -f1)
      TIMESTAMP=$(echo "$line" | cut -f2)

      # Find cutoff timestamp for this session
      CUTOFF=$(echo "$RECALL_CUTOFFS" | awk -F'\t' -v sess="$SESSION" '$1 == sess {print $2; exit}')

      if [ -n "$CUTOFF" ]; then
        # Exclude if timestamp <= cutoff
        LINE_TS=$(echo "$line" | cut -f2)
        if [[ "$LINE_TS" > "$CUTOFF" ]]; then
          FILTERED_RESULTS="$FILTERED_RESULTS$line"$'\n'
        fi
      else
        # No recall in this session, keep all messages
        FILTERED_RESULTS="$FILTERED_RESULTS$line"$'\n'
      fi
    done <<< "$RESULTS"

    RESULTS="$FILTERED_RESULTS"
  fi
fi

if [ -z "$RESULTS" ]; then
  echo "No matches found."
  echo ""
  echo "Query: OR($OR_QUERY) REQUIRE($REQUIRE_QUERY)${EXCLUDE_QUERY:+ EXCLUDE($EXCLUDE_QUERY)}"
  echo ""
  echo "Tips:"
  echo "  • Add more OR synonyms to broaden search"
  echo "  • Use fewer --require terms if too restrictive"
  echo "  • Use underscore for phrases: reset_windows"
  exit 0
fi

# Helper: shorten path (replace $HOME with ~)
shorten_path() {
  echo "$1" | sed "s|^$HOME|~|"
}

# Extract first term for formatting
read -ra OR_TERMS <<< "$OR_QUERY"
FIRST_TERM="${OR_TERMS[0]}"

# Normal search path: group by session, format output
TIMING_FORMAT_START=$(date +%s.%N)
OUTPUT=$(echo "$RESULTS" | python3 "$SCRIPT_DIR/format-results.py" "$SESSIONS" "$MESSAGES" "$CONTEXT" "$FIRST_TERM")
TIMING_FORMAT_END=$(date +%s.%N)
echo "[TIMING] Format output: $(echo "$TIMING_FORMAT_END - $TIMING_FORMAT_START" | bc)s" >&2
echo "[TIMING] TOTAL: $(echo "$TIMING_FORMAT_END - $TIMING_START" | bc)s" >&2
echo "" >&2

# If --recall flag, extract session IDs and run parallel recall
if [ -n "$RECALL_QUESTION" ]; then
  # Extract session IDs from output (format: ~/path | session-id | N matches | timestamp)
  SESSION_IDS=$(echo "$OUTPUT" | grep -E '^\S.* \| [0-9a-f-]{36} \|' | sed 's/.* | \([0-9a-f-]*\) |.*/\1/' | head -$SESSIONS)

  if [ -z "$SESSION_IDS" ]; then
    echo "$OUTPUT"
    exit 0
  fi

  # Build recall args array in format "session-id:question"
  RECALL_ARGS=()
  while IFS= read -r sid; do
    [ -z "$sid" ] && continue
    RECALL_ARGS+=("$sid:$RECALL_QUESTION")
  done <<< "$SESSION_IDS"

  # Debug: show what we're calling
  echo "[DEBUG] Calling recall.sh with ${#RECALL_ARGS[@]} arguments:" >&2
  printf '  "%s"\n' "${RECALL_ARGS[@]}" >&2

  # Run parallel recall
  "$SCRIPT_DIR/recall.sh" "${RECALL_ARGS[@]}"
else
  echo "$OUTPUT"
fi
