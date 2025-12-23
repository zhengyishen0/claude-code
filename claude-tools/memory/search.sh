#!/bin/bash
# Search Claude sessions with boolean query support
# Syntax: memory search "chrome AND click" [--recall "question"]
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
  echo "Error: Missing search query" >&2
  echo "" >&2
  echo "Usage: memory search \"QUERY\" [--recall \"question\"]" >&2
  echo "" >&2
  echo "Query syntax:" >&2
  echo "  Simple: memory search \"chrome click\"" >&2
  echo "  Boolean: memory search \"chrome AND click\"" >&2
  echo "  Complex: memory search \"(chrome OR playwright) AND click NOT test\"" >&2
  echo "" >&2
  echo "Operators: AND, OR, NOT (case-sensitive)" >&2
  exit 1
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

# Execute search
# Strategy: Extract all terms and use ripgrep for initial filtering
# This is fast even on large indices

# Extract unique terms from query (remove operators and parentheses)
all_terms=$(echo "$QUERY" | sed 's/\bAND\b//g; s/\bOR\b//g; s/\bNOT\b//g; s/[()]//g' | tr ' ' '\n' | grep -v '^$')

if [ -z "$all_terms" ]; then
  echo "Error: No search terms in query" >&2
  exit 1
fi

# Build ripgrep alternation pattern (all terms with | operator)
rg_pattern=$(echo "$all_terms" | sed 's/_/./g' | paste -sd '|')
[[ "$rg_pattern" == *"|"* ]] && rg_pattern="($rg_pattern)" || true

# Execute search and get results
TIMING_SEARCH_START=$(date +%s.%N)
RESULTS=$(rg -i "$rg_pattern" "$INDEX_FILE" 2>/dev/null | sort -u || true)
TIMING_SEARCH_END=$(date +%s.%N)
echo "[TIMING] Search + filter: $(echo "$TIMING_SEARCH_END - $TIMING_SEARCH_START" | bc)s" >&2

if [ -z "$RESULTS" ]; then
  echo "No matches found."
  echo ""
  echo "Query: $QUERY"
  echo ""
  echo "Tips:"
  echo "  • Check spelling and capitalization"
  echo "  • Try simpler terms or add synonyms"
  echo "  • Use underscore for phrases: reset_windows"
  exit 0
fi

# Helper: shorten path (replace $HOME with ~)
shorten_path() {
  echo "$1" | sed "s|^$HOME|~|"
}

# Extract first term for output formatting
FIRST_TERM=$(echo "$QUERY" | sed 's/\bAND\b.*//; s/\bOR\b.*//; s/\bNOT\b.*//; s/[()]//g' | awk '{print $1}')

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
