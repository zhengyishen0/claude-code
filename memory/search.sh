#!/bin/bash
# Search Claude sessions
# Simple mode: "word1 word2 word3" → OR-all, ranked by keyword hits
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$SCRIPT_DIR/data"
SESSION_DIR="$HOME/.claude/projects"
INDEX_FILE="$DATA_DIR/memory-index.tsv"

# Parse args
# Debug options (not shown in help): --sessions, --messages, --context
SESSIONS=10
MESSAGES=5
CONTEXT=300
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

# Validation
if [ -z "$QUERY" ]; then
  echo "Usage: memory search \"<keywords>\" [--recall \"question\"]" >&2
  echo "" >&2
  echo "Examples:" >&2
  echo "  memory search \"browser automation\"" >&2
  echo "  memory search \"worktree\" --recall \"how to create?\"" >&2
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

# Format results
OUTPUT=$(echo "$RESULTS" | python3 "$SCRIPT_DIR/format-results.py" "$SESSIONS" "$MESSAGES" "$CONTEXT" "$QUERY" "simple")

# If --recall, run parallel recall
if [ -n "$RECALL_QUESTION" ]; then
  SESSION_IDS=$(echo "$OUTPUT" | grep -E '^\S.* \| [0-9a-f-]{36} \|' | sed 's/.* | \([0-9a-f-]*\) |.*/\1/' | head -$SESSIONS)

  if [ -z "$SESSION_IDS" ]; then
    echo "$OUTPUT"
    exit 0
  fi

  RECALL_ARGS=()
  while IFS= read -r sid; do
    [ -z "$sid" ] && continue
    RECALL_ARGS+=("$sid:$RECALL_QUESTION")
  done <<< "$SESSION_IDS"

  RECALL_OUTPUT=$("$SCRIPT_DIR/recall.sh" "${RECALL_ARGS[@]}")

  if echo "$RECALL_OUTPUT" | grep -q "^RECALL_FALLBACK$"; then
    echo "No relevant answers found. Try different search terms." >&2
  else
    echo "$RECALL_OUTPUT"
  fi
else
  echo "$OUTPUT"
fi
