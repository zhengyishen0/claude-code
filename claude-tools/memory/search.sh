#!/bin/bash
# Search Claude sessions
# Syntax: memory search "OR terms" [--require "required terms"] [--exclude "excluded terms"] [--recall "question"]
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SESSION_DIR="$HOME/.claude/projects"
INDEX_FILE="$HOME/.claude/memory-index.tsv"

# Parse args
SESSIONS=10   # Default: 10 sessions (for recall with filtering)
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
  echo "Error: Missing query (first argument)" >&2
  echo "" >&2
  echo "Usage: memory search \"<query>\" [--recall QUESTION]" >&2
  echo "" >&2
  echo "Query Syntax:" >&2
  echo "  | (pipe)  = OR within group" >&2
  echo "  (space)  = AND between groups" >&2
  echo "" >&2
  echo "Format: \"a1|a2|a3 b1|b2|b3 c1|c2\"" >&2
  echo "Means:  (a1 OR a2 OR a3) AND (b1 OR b2 OR b3) AND (c1 OR c2)" >&2
  echo "" >&2
  echo "Examples:" >&2
  echo "  # Chrome automation implementation" >&2
  echo "  memory search \"chrome|browser|automation implement|build|create\"" >&2
  echo "  → (chrome OR browser OR automation) AND (implement OR build OR create)" >&2
  echo "" >&2
  echo "  # Authentication with JWT/OAuth" >&2
  echo "  memory search \"JWT|OAuth|authentication implement\"" >&2
  echo "  → (JWT OR OAuth OR authentication) AND implement" >&2
  echo "" >&2
  echo "  # Error fixing (not discussion)" >&2
  echo "  memory search \"error|bug fix|solve|patch\"" >&2
  echo "  → (error OR bug) AND (fix OR solve OR patch)" >&2
  echo "" >&2
  echo "  # Simple single-word query (no pipes needed)" >&2
  echo "  memory search \"chrome\"" >&2
  echo "  → chrome" >&2
  exit 1
fi

[ ! -d "$SESSION_DIR" ] && { echo "Error: No Claude sessions found" >&2; exit 1; }

# Get current session to exclude from search results
CURRENT_SESSION_ID="${CLAUDE_SESSION_ID:-}"

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
      # Exclude current session from results
      select($session_id != "'$CURRENT_SESSION_ID'") |
      # Exclude agent sessions (automated explore agent responses)
      select($session_id | startswith("agent-") | not) |
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
      # Exclude current session from results
      select($session_id != "'$CURRENT_SESSION_ID'") |
      # Exclude agent sessions (automated explore agent responses)
      select($session_id | startswith("agent-") | not) |
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

# Search with pipe format: "a1|a2|a3 b1|b2" means (a1 OR a2 OR a3) AND (b1 OR b2)
run_search() {
  # Split query by spaces to get AND groups
  read -ra AND_GROUPS <<< "$QUERY"

  # Start with initial match-all pattern
  CMD="cat '$INDEX_FILE'"

  # Process each AND group
  for group in "${AND_GROUPS[@]}"; do
    # Split group by pipes to get OR terms
    IFS='|' read -ra OR_TERMS <<< "$group"

    # Build OR pattern for this group
    OR_PATTERNS=()
    for term in "${OR_TERMS[@]}"; do
      OR_PATTERNS+=("$(to_pattern "$term")")
    done

    # Combine OR terms into a pattern
    if [ ${#OR_PATTERNS[@]} -eq 1 ]; then
      # Single term, no parentheses needed
      PATTERN="${OR_PATTERNS[0]}"
    else
      # Multiple terms, use (term1|term2|term3) format
      PATTERN=$(IFS='|'; echo "${OR_PATTERNS[*]}")
      PATTERN="($PATTERN)"
    fi

    # Add this AND filter to the pipeline
    CMD="$CMD | rg -i '$PATTERN'"
  done

  eval "$CMD" 2>/dev/null || true
}

# Execute search
TIMING_SEARCH_START=$(date +%s.%N)
RESULTS=$(run_search | sort -u || true)

TIMING_SEARCH_END=$(date +%s.%N)
echo "[TIMING] Search + filter: $(echo "$TIMING_SEARCH_END - $TIMING_SEARCH_START" | bc)s" >&2

if [ -z "$RESULTS" ]; then
  echo "No matches found."
  echo ""
  echo "Query: $QUERY"
  echo ""
  echo "Tips:"
  echo "  • Add more OR synonyms: chrome|browser|firefox"
  echo "  • Reduce AND groups if too restrictive"
  echo "  • Use underscore for phrases: reset_windows"
  exit 0
fi

# Helper: shorten path (replace $HOME with ~)
shorten_path() {
  echo "$1" | sed "s|^$HOME|~|"
}

# Extract first term for formatting (from first AND group, first OR term)
FIRST_GROUP="${QUERY%% *}"  # Get first space-separated group
FIRST_TERM="${FIRST_GROUP%%|*}"  # Get first pipe-separated term

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

  # Run parallel recall and capture output
  RECALL_OUTPUT=$("$SCRIPT_DIR/recall.sh" "${RECALL_ARGS[@]}")

  # Check if recall returned fallback marker (no good answers)
  if echo "$RECALL_OUTPUT" | grep -q "^RECALL_FALLBACK$"; then
    echo "" >&2
    echo "💡 No relevant answers found. Try:" >&2
    echo "   • Refine your search query (use different terms or --require/--exclude)" >&2
    echo "   • Rephrase your recall question" >&2
    echo "   • Run search without --recall to see raw snippets: memory search \"$OR_QUERY\"" >&2
    echo "" >&2
  else
    echo "$RECALL_OUTPUT"
  fi
else
  echo "$OUTPUT"
fi
