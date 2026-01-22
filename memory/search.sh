#!/bin/bash
# Search Claude sessions
# Simple mode: "word1 word2 word3" → OR-all, ranked by keyword hits
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

: "${CLAUDE_DIR:=$HOME/.claude}"

DATA_DIR="$SCRIPT_DIR/data"
SESSION_DIR="$CLAUDE_DIR/projects"
INDEX_FILE="$DATA_DIR/memory-index.tsv"

# Parse args
# Debug options (not shown in help): --sessions, --messages, --context
SESSIONS=10
MESSAGES=5
CONTEXT=300
QUERY=""
RECALL_QUESTION=""
NLP_MODE="none"  # none, porter, snowball, lemma, hybrid

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
    --recall)
      RECALL_QUESTION="$2"
      shift 2
      ;;
    --nlp)
      NLP_MODE="$2"
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

# Validation
if [ -z "$QUERY" ]; then
  echo "Usage: memory search \"<keywords>\" [--nlp MODE] [--recall \"question\"]" >&2
  echo "" >&2
  echo "Options:" >&2
  echo "  --nlp MODE    Text normalization: none (default), porter, snowball, lemma, hybrid" >&2
  echo "                - porter:   Fast stemming (running→run, but ran→ran)" >&2
  echo "                - snowball: Balanced stemming, multi-language capable" >&2
  echo "                - lemma:    Dictionary lookup (running→run, ran→run)" >&2
  echo "                - hybrid:   Best accuracy (lemma + stemming fallback)" >&2
  echo "" >&2
  echo "Workflow:" >&2
  echo "  1. Search first:  memory search \"browser automation\"" >&2
  echo "  2. Try NLP mode:  memory search \"ran specifications\" --nlp hybrid" >&2
  echo "  3. Then recall:   memory search \"browser automation\" --recall \"how to click?\"" >&2
  exit 1
fi

[ ! -d "$SESSION_DIR" ] && { echo "Error: No Claude sessions found" >&2; exit 1; }

# Get current session to exclude from search results
CURRENT_SESSION_ID="${CLAUDE_SESSION_ID:-}"

# Build full index with jq
build_full_index() {
  echo "Building index..." >&2
  find "$SESSION_DIR" -name "*.jsonl" -type f 2>/dev/null | while read -r file; do
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
      select($text | test("^\\[[0-9]+/[0-9]+\\]\\s+[a-f0-9]{7}\\s+•") | not) |
      ($filepath | split("/") | last | split(".jsonl") | first) as $session_id |
      select($session_id != "'"$CURRENT_SESSION_ID"'") |
      select($session_id | startswith("agent-") | not) |
      [$session_id, .timestamp, .type, $text, .cwd // "unknown"] | @tsv
    ' 2>/dev/null > "$INDEX_FILE"
  echo "Index built: $(wc -l < "$INDEX_FILE" | tr -d ' ') messages" >&2
}

# Incremental update
update_index() {
  local new_files="$1"
  local non_fork_files=$(echo "$new_files" | while read -r file; do
    if [ -f "$file" ] && ! head -1 "$file" | jq -e 'select(.type == "queue-operation")' >/dev/null 2>&1; then
      echo "$file"
    fi
  done)

  if [ -z "$non_fork_files" ]; then
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
      select($text | test("^\\[[0-9]+/[0-9]+\\]\\s+[a-f0-9]{7}\\s+•") | not) |
      ($filepath | split("/") | last | split(".jsonl") | first) as $session_id |
      select($session_id != "'"$CURRENT_SESSION_ID"'") |
      select($session_id | startswith("agent-") | not) |
      [$session_id, .timestamp, .type, $text, .cwd // "unknown"] | @tsv
    ' 2>/dev/null >> "$INDEX_FILE" || true
}

# Check if index needs update
if [ ! -f "$INDEX_FILE" ]; then
  build_full_index
else
  NEW_FILES=$(find "$SESSION_DIR" -name "*.jsonl" -newer "$INDEX_FILE" 2>/dev/null || true)
  if [ -n "$NEW_FILES" ]; then
    update_index "$NEW_FILES"
  fi
fi

# Convert underscore phrases to regex
to_pattern() {
  echo "$1" | sed 's/_/./g'
}

# Simple search: OR all keywords
run_search() {
  read -ra KEYWORDS <<< "$QUERY"

  OR_PATTERNS=()
  for keyword in "${KEYWORDS[@]}"; do
    OR_PATTERNS+=("$(to_pattern "$keyword")")
  done

  if [ ${#OR_PATTERNS[@]} -eq 1 ]; then
    PATTERN="${OR_PATTERNS[0]}"
  else
    PATTERN=$(IFS='|'; echo "${OR_PATTERNS[*]}")
    PATTERN="($PATTERN)"
  fi

  rg -i "$PATTERN" "$INDEX_FILE" 2>/dev/null || true
}

# Execute search
RESULTS=$(run_search | sort -u || true)

if [ -z "$RESULTS" ]; then
  echo "No matches found for: $QUERY"
  exit 0
fi

# Format results and capture session IDs from stderr
TEMP_IDS=$(mktemp)
OUTPUT=$(echo "$RESULTS" | python3 "$SCRIPT_DIR/format-results.py" "$SESSIONS" "$MESSAGES" "$CONTEXT" "$QUERY" "simple" "$NLP_MODE" 2>"$TEMP_IDS")
SESSION_IDS=$(cat "$TEMP_IDS")
rm -f "$TEMP_IDS"

# If --recall, run parallel recall on matching sessions
if [ -n "$RECALL_QUESTION" ]; then
  if [ -z "$SESSION_IDS" ]; then
    echo "No sessions to recall."
    exit 0
  fi

  # Convert comma-separated IDs to array
  IFS=',' read -ra ID_ARRAY <<< "$SESSION_IDS"

  # Call recall.sh with session IDs and question
  "$SCRIPT_DIR/recall.sh" "${ID_ARRAY[@]}" "$RECALL_QUESTION"
else
  # Normal search output with footer tip
  echo "$OUTPUT"
  echo ""
  echo "Tip: If snippets above answer your question, you're done. Otherwise use --recall \"question\" for deeper answers."
fi
