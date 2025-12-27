#!/bin/bash
# Search Claude sessions with dual-mode boolean query system
# Simple mode (no parentheses): "chrome AND click" uses ripgrep pipeline
# Complex mode (with parentheses): "(chrome OR code) AND click" uses pure jq boolean logic
# Syntax: memory search "query" [--recall "question"]
# OR legacy: memory search "OR terms" --require "required terms" [--exclude "excluded terms"] [--recall "question"]
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
# Legacy flags
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
  echo "Usage: memory search \"query\" [--recall \"question\"]" >&2
  echo "   Or: memory search \"OR terms\" --require \"required terms\" [--exclude \"excluded terms\"] [--recall \"question\"]" >&2
  echo "" >&2
  echo "Examples (new dual-mode syntax):" >&2
  echo "  memory search \"chrome AND click\"" >&2
  echo "  memory search \"(chrome OR playwright) AND (fix OR bug)\"" >&2
  echo "  memory search \"chrome AND click --recall 'How to fix click issues?'\"" >&2
  echo "" >&2
  echo "Examples (legacy syntax):" >&2
  echo "  memory search \"asus laptop\" --require \"spec\"" >&2
  echo "  memory search \"chrome playwright\" --require \"click\" --recall \"How to fix click issues?\"" >&2
  exit 1
fi

# Detect mode: if --require or --exclude provided, use legacy mode
if [ -n "$REQUIRE_QUERY" ] || [ -n "$EXCLUDE_QUERY" ]; then
  OR_QUERY="$QUERY"
  # Legacy mode will be handled later
fi

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

# Detect if query has parentheses (complex mode) or AND/OR/NOT operators (simple mode)
has_parentheses() {
  [[ "$1" =~ \( ]] || [[ "$1" =~ \) ]]
}

# Check if query uses boolean operators
has_boolean_operators() {
  [[ "$1" =~ [[:space:]]AND[[:space:]] ]] || [[ "$1" =~ [[:space:]]OR[[:space:]] ]] || [[ "$1" =~ [[:space:]]NOT[[:space:]] ]]
}

# Legacy mode: space-separated terms become OR, then REQUIRE/EXCLUDE filters
run_legacy_search() {
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

# Determine search mode and execute
TIMING_SEARCH_START=$(date +%s.%N)

if [ -n "$OR_QUERY" ]; then
  # Legacy mode (--require or --exclude was specified)
  RESULTS=$(run_legacy_search | sort -u || true)
elif has_parentheses "$QUERY" || has_boolean_operators "$QUERY"; then
  # New dual-mode: use ripgrep pipeline for queries with boolean operators or parentheses
  # Extract terms from query (handle parentheses, AND, OR, NOT)
  # Apply AND logic across all terms

  # Extract all terms, removing operators and parentheses
  query_clean=$(echo "$QUERY" | sed -E 's/[\(\)]+/ /g; s/(AND|OR|NOT)/ /g')
  read -ra terms <<< "$query_clean"

  # Filter the index - all terms must match (conservative AND approach)
  # Build initial ripgrep pipeline with first term
  CMD="rg -i '$(to_pattern "${terms[0]}")' '$INDEX_FILE'"

  # Chain additional filters for remaining terms
  for ((i=1; i<${#terms[@]}; i++)); do
    if [ -n "${terms[$i]}" ]; then
      CMD="$CMD | rg -i '$(to_pattern "${terms[$i]}")'"
    fi
  done

  RESULTS=$(eval "$CMD" 2>/dev/null | sort -u || true)
else
  # Single term search
  RESULTS=$(rg -i "$(to_pattern "$QUERY")" "$INDEX_FILE" 2>/dev/null | sort -u || true)
fi

TIMING_SEARCH_END=$(date +%s.%N)
echo "[TIMING] Search + filter: $(echo "$TIMING_SEARCH_END - $TIMING_SEARCH_START" | bc)s" >&2

# Post-process: Exclude current session and messages at/before recall outputs
if [ -n "$RESULTS" ]; then
  # Strategy 1: Exclude entire current session (tracked by PreToolUse hook via SSE port)
  CURRENT_SESSION=""
  if [ -n "$CLAUDE_CODE_SSE_PORT" ] && [ -f "$HOME/.claude/session-ports/$CLAUDE_CODE_SSE_PORT.txt" ]; then
    CURRENT_SESSION=$(cat "$HOME/.claude/session-ports/$CLAUDE_CODE_SSE_PORT.txt")
  fi

  if [ -n "$CURRENT_SESSION" ]; then
    RESULTS=$(echo "$RESULTS" | grep -v "^$CURRENT_SESSION	" || true)
  fi

  # Strategy 2: Find query sessions (messages indicating memory search/recall usage)
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
  if [ -n "$OR_QUERY" ]; then
    echo "Query: OR($OR_QUERY) REQUIRE($REQUIRE_QUERY)${EXCLUDE_QUERY:+ EXCLUDE($EXCLUDE_QUERY)}"
    echo ""
    echo "Tips:"
    echo "  • Add more OR synonyms to broaden search"
    echo "  • Use fewer --require terms if too restrictive"
    echo "  • Use underscore for phrases: reset_windows"
  else
    echo "Query: $QUERY"
    echo ""
    echo "Tips:"
    echo "  • Try simpler terms to broaden search"
    echo "  • Use OR to find alternative terms: (chrome OR browser)"
    echo "  • Use underscore for phrases: reset_windows"
  fi
  exit 0
fi

# Helper: shorten path (replace $HOME with ~)
shorten_path() {
  echo "$1" | sed "s|^$HOME|~|"
}

# Extract first term for formatting
if [ -n "$OR_QUERY" ]; then
  read -ra OR_TERMS <<< "$OR_QUERY"
  FIRST_TERM="${OR_TERMS[0]}"
else
  # Extract first word from QUERY (skip boolean operators and parens)
  FIRST_TERM=$(echo "$QUERY" | sed -E 's/[\(\)]+/ /g; s/(AND|OR|NOT)//g' | awk '{print $1}')
fi

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

  # Build recall args in format "session-id:question"
  RECALL_ARGS=""
  while IFS= read -r sid; do
    [ -z "$sid" ] && continue
    RECALL_ARGS="$RECALL_ARGS \"$sid:$RECALL_QUESTION\""
  done <<< "$SESSION_IDS"

  # Run parallel recall
  eval "$SCRIPT_DIR/recall.sh $RECALL_ARGS"
else
  echo "$OUTPUT"
fi
