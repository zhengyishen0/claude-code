#!/bin/bash
# Search Claude sessions with incremental indexing
# Syntax: "term1|term2 and_term -not_term"
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SESSION_DIR="$HOME/.claude/projects"
INDEX_FILE="$HOME/.claude/memory-index.tsv"

# Parse args
LIMIT=15  # Default: 15 messages per session
QUERY=""
RAW_MODE=false  # Default: summarize output

while [[ $# -gt 0 ]]; do
  case "$1" in
    --limit)
      LIMIT="$2"
      shift 2
      ;;
    --raw)
      RAW_MODE=true
      shift
      ;;
    *)
      QUERY="$1"
      shift
      ;;
  esac
done

[ -z "$QUERY" ] && {
  echo "Usage: memory search [--limit N] [--raw] \"pattern\"" >&2
  echo "Run 'memory --help' for full documentation" >&2
  exit 1
}

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
  echo "$new_files" | xargs -I{} rg -N '"type":"(user|assistant)"' {} 2>/dev/null | \
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

# Parse query into terms
read -ra TERMS <<< "$QUERY"
FIRST="${TERMS[0]}"
[[ "$FIRST" == *"|"* ]] && FIRST="($FIRST)"

# Build search pipeline
CMD="rg -i '$FIRST' '$INDEX_FILE'"
for term in "${TERMS[@]:1}"; do
  if [[ "$term" == -* ]]; then
    CMD="$CMD | grep -iv '${term:1}'"
  else
    CMD="$CMD | rg -i '$term'"
  fi
done

# Search, dedup, group by session
RESULTS=$(eval "$CMD" 2>/dev/null | sort -u || true)

if [ -z "$RESULTS" ]; then
  echo "No matches found for: $QUERY"
  exit 0
fi

# Group by session, sort by latest timestamp
# Pass LIMIT and QUERY as awk variables
# Snippet context: 400 chars before + 400 chars after = 800 total
RAW_OUTPUT=$(echo "$RESULTS" | awk -F'\t' -v limit="$LIMIT" -v query="$QUERY" '
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

    # Extract snippet if text is long (medium: 400 before + 400 after)
    if (length(text) > 800) {
      # Find query position (case-insensitive)
      lower_text = tolower(text)
      lower_query = tolower(query)
      pos = index(lower_text, lower_query)

      if (pos > 0) {
        # Extract 400 chars before + 400 after match
        start = (pos > 400) ? pos - 400 : 1
        snippet = substr(text, start, 800)

        # Add ellipsis for truncation
        if (start > 1) snippet = "..." snippet
        if (start + 800 < length(text)) snippet = snippet "..."
      } else {
        # No direct match, show beginning
        snippet = substr(text, 1, 800) "..."
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

# Default: summarize; --raw skips summarization
if [ "$RAW_MODE" = "true" ]; then
  echo "$OUTPUT"
else
  echo "Summarizing $SESSION_COUNT sessions..." >&2
  # Pipe output through summarize.sh
  # Note: set +e temporarily to avoid SIGPIPE exit
  set +e
  echo "$OUTPUT" | "$SCRIPT_DIR/summarize.sh"
  set -e
fi
