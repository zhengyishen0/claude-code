#!/bin/bash
# Search Claude sessions with incremental indexing
# Syntax: memory search "OR terms" --and "AND terms" [--not "NOT terms"] [--recall "question"]
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SESSION_DIR="$HOME/.claude/projects"
INDEX_FILE="$HOME/.claude/memory-index.tsv"

# Parse args
LIMIT=5  # Default: 5 sessions
OR_QUERY=""
AND_QUERY=""
NOT_QUERY=""
RECALL_QUESTION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --limit)
      LIMIT="$2"
      shift 2
      ;;
    --and)
      AND_QUERY="$2"
      shift 2
      ;;
    --not)
      NOT_QUERY="$2"
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
      OR_QUERY="$1"
      shift
      ;;
  esac
done

# Validation: both OR and AND are required
if [ -z "$OR_QUERY" ]; then
  echo "Error: Missing OR terms (first argument)" >&2
  echo "" >&2
  echo "Usage: memory search \"OR terms\" --and \"AND terms\" [--not \"NOT terms\"] [--recall \"question\"]" >&2
  echo "" >&2
  echo "Examples:" >&2
  echo "  memory search \"asus laptop\" --and \"spec\"" >&2
  echo "  memory search \"chrome playwright\" --and \"click\" --recall \"How to fix click issues?\"" >&2
  exit 1
fi

if [ -z "$AND_QUERY" ]; then
  echo "Error: Missing --and flag (required)" >&2
  echo "" >&2
  echo "Usage: memory search \"OR terms\" --and \"AND terms\" [--not \"NOT terms\"] [--recall \"question\"]" >&2
  echo "" >&2
  echo "Examples:" >&2
  echo "  memory search \"asus laptop\" --and \"spec\"" >&2
  echo "  memory search \"chrome playwright\" --and \"click\" --recall \"How to fix click issues?\"" >&2
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

# Convert underscore phrases to regex: "Tesla_Model_3" -> "Tesla.Model.3"
to_pattern() {
  echo "$1" | sed 's/_/./g'
}

# Parse space-separated terms into arrays
read -ra OR_TERMS <<< "$OR_QUERY"
read -ra AND_TERMS <<< "$AND_QUERY"
read -ra NOT_TERMS <<< "$NOT_QUERY"

# Build OR pattern from first arg terms
OR_PATTERNS=()
for term in "${OR_TERMS[@]}"; do
  OR_PATTERNS+=("$(to_pattern "$term")")
done
OR_PATTERN=$(IFS='|'; echo "${OR_PATTERNS[*]}")
[[ "$OR_PATTERN" == *"|"* ]] && OR_PATTERN="($OR_PATTERN)"

# Build AND pattern (must match at least one of these)
AND_PATTERNS=()
for term in "${AND_TERMS[@]}"; do
  AND_PATTERNS+=("$(to_pattern "$term")")
done
AND_PATTERN=$(IFS='|'; echo "${AND_PATTERNS[*]}")
[[ "$AND_PATTERN" == *"|"* ]] && AND_PATTERN="($AND_PATTERN)"

# Build search pipeline: OR first, then AND filter, then NOT filters
CMD="rg -i '$OR_PATTERN' '$INDEX_FILE' | rg -i '$AND_PATTERN'"
for term in "${NOT_TERMS[@]}"; do
  pattern=$(to_pattern "$term")
  CMD="$CMD | grep -iv '$pattern'"
done

# Search, dedup, group by session
TIMING_SEARCH_START=$(date +%s.%N)
RESULTS=$(eval "$CMD" 2>/dev/null | sort -u || true)
TIMING_SEARCH_END=$(date +%s.%N)
echo "[TIMING] Search + filter: $(echo "$TIMING_SEARCH_END - $TIMING_SEARCH_START" | bc)s" >&2

if [ -z "$RESULTS" ]; then
  echo "No matches found."
  echo ""
  echo "Query: OR($OR_QUERY) AND($AND_QUERY)${NOT_QUERY:+ NOT($NOT_QUERY)}"
  echo ""
  echo "Tips:"
  echo "  • Add more OR synonyms to broaden search"
  echo "  • Use underscore for phrases: reset_windows"
  exit 0
fi

# Helper: shorten path (replace $HOME with ~)
shorten_path() {
  echo "$1" | sed "s|^$HOME|~|"
}


# Normal search path: group by session, format output
TIMING_FORMAT_START=$(date +%s.%N)
FIRST_TERM="${OR_TERMS[0]}"
OUTPUT=$(echo "$RESULTS" | python3 "$SCRIPT_DIR/format-results.py" "$LIMIT" "$FIRST_TERM")
TIMING_FORMAT_END=$(date +%s.%N)
echo "[TIMING] Format output: $(echo "$TIMING_FORMAT_END - $TIMING_FORMAT_START" | bc)s" >&2
echo "[TIMING] TOTAL: $(echo "$TIMING_FORMAT_END - $TIMING_START" | bc)s" >&2
echo "" >&2

# If --recall flag, extract session IDs and run parallel recall
if [ -n "$RECALL_QUESTION" ]; then
  # Extract session IDs from output (format: ~/path | session-id)
  SESSION_IDS=$(echo "$OUTPUT" | grep -E '^\S.* \| [0-9a-f-]{36}$' | sed 's/.* | //' | head -$LIMIT)

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
