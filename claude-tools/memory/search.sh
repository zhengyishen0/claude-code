#!/bin/bash
# Search Claude sessions with incremental indexing
# Syntax: memory search "OR terms" --and "AND terms" [--not "NOT terms"]
# - First arg: OR terms (broaden - synonyms/alternatives)
# - --and: AND terms (narrow - must have at least one)
# - --not: NOT terms (filter - exclude these)
# - Underscore joins words into phrases: reset_windows
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SESSION_DIR="$HOME/.claude/projects"
INDEX_FILE="$HOME/.claude/memory-index.tsv"

# Parse args
LIMIT=5  # Default: 5 messages per session (compact for raw mode)
OR_QUERY=""
AND_QUERY=""
NOT_QUERY=""
SUMMARIZE=false  # Default: raw output (fast)

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
    --summary|-s)
      SUMMARIZE=true
      shift
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
  echo "Usage: memory search \"OR terms\" --and \"AND terms\" [--not \"NOT terms\"]" >&2
  echo "" >&2
  echo "Examples:" >&2
  echo "  memory search \"asus laptop machine\" --and \"spec\"" >&2
  echo "  memory search \"chrome playwright\" --and \"click\" --not \"test\"" >&2
  exit 1
fi

if [ -z "$AND_QUERY" ]; then
  echo "Error: Missing --and flag (required)" >&2
  echo "" >&2
  echo "Usage: memory search \"OR terms\" --and \"AND terms\" [--not \"NOT terms\"]" >&2
  echo "" >&2
  echo "Examples:" >&2
  echo "  memory search \"asus laptop machine\" --and \"spec\"" >&2
  echo "  memory search \"chrome playwright\" --and \"click\" --not \"test\"" >&2
  exit 1
fi

[ ! -d "$SESSION_DIR" ] && { echo "Error: No Claude sessions found" >&2; exit 1; }

# Build full index with jq
# Index format: session_id \t timestamp \t type \t text \t project_path
build_full_index() {
  echo "Building index..." >&2
  rg -N '"type":"(user|assistant)"' -g '*.jsonl' "$SESSION_DIR" 2>/dev/null | \
    cut -d: -f2- | \
    jq -rs '
      .[] |
      select(.type == "user" or .type == "assistant") |
      (.message.content |
        if type == "array" then
          [.[] | select(.type == "text") | .text] | join(" ")
        elif type == "string" then .
        else "" end
      ) as $text |
      select($text | length > 10) |
      select($text | test("<ide_|\\[Request interrupted|New environment|API Error|Limit reached|Caveat:|<bash-") | not) |
      [.sessionId // .agentId // "unknown", .timestamp, .type, $text, .cwd // "unknown"] | @tsv
    ' 2>/dev/null > "$INDEX_FILE"
  echo "Index built: $(wc -l < "$INDEX_FILE" | tr -d ' ') messages" >&2
}

# Incremental update - process only new files
update_index() {
  local new_files="$1"
  local count=$(echo "$new_files" | wc -l | tr -d ' ')
  echo "Updating index ($count files)..." >&2
  echo "$new_files" | xargs -I{} rg -N -H '"type":"(user|assistant)"' {} 2>/dev/null | \
    cut -d: -f2- | \
    jq -rs '
      .[] |
      select(.type == "user" or .type == "assistant") |
      (.message.content |
        if type == "array" then
          [.[] | select(.type == "text") | .text] | join(" ")
        elif type == "string" then .
        else "" end
      ) as $text |
      select($text | length > 10) |
      select($text | test("<ide_|\\[Request interrupted|New environment|API Error|Limit reached|Caveat:|<bash-") | not) |
      [.sessionId // .agentId // "unknown", .timestamp, .type, $text, .cwd // "unknown"] | @tsv
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

# Convert underscore phrases to regex: "Tesla_Model_3" -> "Tesla.Model.3"
# This matches the phrase with any separator (space, dash, etc.)
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
RESULTS=$(eval "$CMD" 2>/dev/null | sort -u || true)

if [ -z "$RESULTS" ]; then
  echo "No matches found."
  echo ""
  echo "Query: OR($OR_QUERY) AND($AND_QUERY)${NOT_QUERY:+ NOT($NOT_QUERY)}"
  echo ""
  echo "Tips:"
  echo "  • Add more OR synonyms to broaden search"
  echo "  • Use underscore for phrases: reset_windows"
  echo "  • Try 'memory recall <session-id>:question' to ask a session directly"
  exit 0
fi

# Group by session, sort by latest timestamp
# Pass LIMIT and first OR term as query for snippet extraction
# Snippet context: 100 chars before + 100 chars after = 200 total (compact for raw mode)
FIRST_TERM="${OR_TERMS[0]}"
RAW_OUTPUT=$(echo "$RESULTS" | awk -F'\t' -v limit="$LIMIT" -v query="$FIRST_TERM" '
{
  session = $1
  timestamp = $2
  type = $3
  text = $4
  project = $5

  # Track count per session
  count[session]++

  # Track latest timestamp per session
  if (timestamp > latest[session]) latest[session] = timestamp

  # Track project per session (first seen)
  if (!(session in projects)) projects[session] = project

  # Store messages (up to limit per session) with snippet extraction
  if (count[session] <= limit) {
    snippet = text

    # Extract snippet if text is long (compact: 100 before + 100 after)
    if (length(text) > 200) {
      # Find query position (case-insensitive)
      lower_text = tolower(text)
      lower_query = tolower(query)
      pos = index(lower_text, lower_query)

      if (pos > 0) {
        # Extract 100 chars before + 100 after match
        start = (pos > 100) ? pos - 100 : 1
        snippet = substr(text, start, 200)

        # Add ellipsis for truncation
        if (start > 1) snippet = "..." snippet
        if (start + 200 < length(text)) snippet = snippet "..."
      } else {
        # No direct match, show beginning
        snippet = substr(text, 1, 200) "..."
      }
    }

    messages[session] = messages[session] type "\t" snippet "\n"
  }
}
END {
  # Sort sessions by latest timestamp (descending)
  n = 0
  for (s in latest) {
    sessions[n] = latest[s] "\t" s
    n++
  }
  # Bubble sort (simple, n is small)
  for (i = 0; i < n-1; i++) {
    for (j = i+1; j < n; j++) {
      if (sessions[i] < sessions[j]) {
        tmp = sessions[i]
        sessions[i] = sessions[j]
        sessions[j] = tmp
      }
    }
  }

  # Print session count first (for info)
  print "SESSION_COUNT:" n

  # Print grouped results
  total_matches = 0
  for (i = 0; i < n; i++) {
    split(sessions[i], parts, "\t")
    s = parts[2]

    print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print "Session: " s " | Project: " projects[s]
    print "Matches: " count[s] " | Latest: " latest[s]
    print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Print messages
    split(messages[s], lines, "\n")
    for (j = 1; j <= length(lines); j++) {
      if (lines[j] != "") {
        split(lines[j], msg, "\t")
        role = (msg[1] == "user") ? "[user]" : "[asst]"
        txt = msg[2]
        print role " " txt
      }
    }

    if (count[s] > limit) {
      print "... and " (count[s] - limit) " more"
    }
    print ""

    total_matches += count[s]
  }

  print "Found " total_matches " matches across " n " sessions"
}')

# Extract session count and output
SESSION_COUNT=$(echo "$RAW_OUTPUT" | head -1 | cut -d: -f2)
OUTPUT=$(echo "$RAW_OUTPUT" | tail -n +2)

# Default: raw output; --summary enables summarization
if [ "$SUMMARIZE" = "true" ]; then
  echo "Summarizing $SESSION_COUNT sessions..." >&2
  # Pipe output through summarize.sh
  # Note: set +e temporarily to avoid SIGPIPE exit
  set +e
  echo "$OUTPUT" | "$SCRIPT_DIR/summarize.sh"
  set -e
else
  echo "$OUTPUT"
fi
