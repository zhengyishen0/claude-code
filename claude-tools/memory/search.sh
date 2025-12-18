#!/bin/bash
# Search Claude sessions with incremental indexing
# Syntax: "term1|term2 and_term -not_term"
set -e

SESSION_DIR="$HOME/.claude/projects"
INDEX_FILE="$HOME/.claude/memory-index.tsv"

# Parse args
SHOW_ALL=false
QUERY=""

for arg in "$@"; do
  case "$arg" in
    --all|-a)
      SHOW_ALL=true
      ;;
    *)
      QUERY="$arg"
      ;;
  esac
done

[ -z "$QUERY" ] && {
  echo "Usage: memory search [--all] \"pattern\"" >&2
  echo "" >&2
  echo "Flags:" >&2
  echo "  --all, -a      Show all matches (no truncation)" >&2
  echo "" >&2
  echo "Syntax:" >&2
  echo "  term1|term2    OR  (first term, rg pattern)" >&2
  echo "  term           AND (space-separated)" >&2
  echo "  -term          NOT (dash prefix)" >&2
  echo "" >&2
  echo "Examples:" >&2
  echo "  memory search \"error\"" >&2
  echo "  memory search \"chrome|playwright\"" >&2
  echo "  memory search --all \"chrome|playwright click -test\"" >&2
  exit 1
}

[ ! -d "$SESSION_DIR" ] && { echo "Error: No Claude sessions found" >&2; exit 1; }

# Build full index with jq
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
      [.sessionId // .agentId // "unknown", .timestamp, .type, ($text | .[0:200])] | @tsv
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
      [.sessionId // .agentId // "unknown", .timestamp, .type, ($text | .[0:200])] | @tsv
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
# Pass SHOW_ALL as awk variable
echo "$RESULTS" | awk -F'\t' -v show_all="$SHOW_ALL" '
{
  session = $1
  timestamp = $2
  type = $3
  text = $4

  # Track count per session
  count[session]++

  # Track latest timestamp per session
  if (timestamp > latest[session]) latest[session] = timestamp

  # Store messages (up to limit per session unless show_all)
  limit = (show_all == "true") ? 999999 : 10
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

  # Print grouped results
  total_matches = 0
  limit = (show_all == "true") ? 999999 : 10
  for (i = 0; i < n; i++) {
    split(sessions[i], parts, "\t")
    s = parts[2]

    print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print "Session: " s
    print "Matches: " count[s] " | Latest: " latest[s]
    print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Print messages
    split(messages[s], lines, "\n")
    for (j = 1; j <= length(lines); j++) {
      if (lines[j] != "") {
        split(lines[j], msg, "\t")
        role = (msg[1] == "user") ? "[user]" : "[asst]"
        # Truncate text (80 chars default, 200 if show_all)
        txt = msg[2]
        max_len = (show_all == "true") ? 200 : 80
        if (length(txt) > max_len) txt = substr(txt, 1, max_len - 3) "..."
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
}'
