#!/bin/bash
# Search Claude sessions with incremental indexing
# Syntax: "term1|term2 and_term -not_term"
set -e

SESSION_DIR="$HOME/.claude/projects"
INDEX_FILE="$HOME/.claude/memory-index.tsv"

# Parse args
LIMIT=5  # Default: 5 messages per session
QUERY=""
AUTO_SUMMARIZE_THRESHOLD=20  # Auto-summarize if more than N sessions

while [[ $# -gt 0 ]]; do
  case "$1" in
    --limit)
      LIMIT="$2"
      shift 2
      ;;
    *)
      QUERY="$1"
      shift
      ;;
  esac
done

[ -z "$QUERY" ] && {
  echo "Usage: memory search [--limit N] \"pattern\"" >&2
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
# Pass LIMIT as awk variable
RAW_OUTPUT=$(echo "$RESULTS" | awk -F'\t' -v limit="$LIMIT" '
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

  # Store messages (up to limit per session)
  if (count[session] <= limit) {
    messages[session] = messages[session] type "\t" text "\n"
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

  # Print session count first (for auto-summarize check)
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

# Extract session count and check for auto-summarize
SESSION_COUNT=$(echo "$RAW_OUTPUT" | head -1 | cut -d: -f2)
OUTPUT=$(echo "$RAW_OUTPUT" | tail -n +2)

if [ "$SESSION_COUNT" -gt "$AUTO_SUMMARIZE_THRESHOLD" ] && command -v claude &>/dev/null; then
  echo "Found $SESSION_COUNT sessions (>${AUTO_SUMMARIZE_THRESHOLD}). Auto-summarizing with haiku..." >&2

  # Truncate to top 15 sessions worth of output for summarization
  SUMMARY_INPUT=$(echo "$OUTPUT" | head -150)

  SUMMARY=$(echo "$SUMMARY_INPUT" | claude --model haiku -p "Summarize each session. Include: main topic, key files/functions mentioned, specific solutions or fixes. Format: SESSION_ID: [topic] - [key details]. One line per session. Output ONLY summaries." --max-turns 1 --dangerously-skip-permissions 2>&1)

  # Check if summary succeeded (look for session ID pattern with or without brackets)
  if echo "$SUMMARY" | grep -qE "^[a-f0-9-]{8,}"; then
    echo "$SUMMARY"
  else
    # Fallback to raw output
    echo "(Summarization failed, showing raw results)" >&2
    echo "$OUTPUT"
  fi
else
  echo "$OUTPUT"
fi
