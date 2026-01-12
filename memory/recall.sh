#!/bin/bash
# Recall sessions - internal module for search --recall
# Not intended to be called directly (use: claude --resume "id" -p "question")
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INDEX_FILE="$SCRIPT_DIR/data/memory-index.tsv"

# Get session date from index
get_session_date() {
  local session_id="$1"
  local timestamp=$(grep "^$session_id" "$INDEX_FILE" 2>/dev/null | head -1 | cut -f2)
  echo "$timestamp" | cut -d'T' -f1 | awk -F'-' '{
    months["01"]="Jan"; months["02"]="Feb"; months["03"]="Mar"; months["04"]="Apr";
    months["05"]="May"; months["06"]="Jun"; months["07"]="Jul"; months["08"]="Aug";
    months["09"]="Sep"; months["10"]="Oct"; months["11"]="Nov"; months["12"]="Dec";
    print months[$2] " " int($3)
  }'
}

# Recall a single session
recall_session() {
  local session_id="$1"
  local question="$2"

  # Verify session exists in index
  if ! grep -q "^$session_id" "$INDEX_FILE" 2>/dev/null; then
    echo "Error: Session not found: $session_id" >&2
    return 1
  fi

  local formatted_prompt="Answer concisely:

[One sentence summary]

• Key point 1
• Key point 2
• Key point 3 (max 5 bullets)

Rules:
- No headers or markdown sections
- Keep under 150 tokens
- If no relevant info, respond ONLY: \"I don't have information about that.\"

Question: $question"

  claude --model haiku --resume "$session_id" -p "$formatted_prompt" --no-session-persistence --output-format json 2>/dev/null | jq -r '.result // empty'
}

# Batch recall with parallel execution
batch_recall() {
  local queries=("$@")
  local total=${#queries[@]}
  local timeout=15  # seconds

  if [ $total -eq 0 ]; then
    echo "Error: No queries" >&2
    return 1
  fi

  # Single query
  if [ $total -eq 1 ]; then
    local query="${queries[0]}"
    local session_id="${query%%:*}"
    local question="${query#*:}"
    recall_session "$session_id" "$question"
    return
  fi

  # Multiple queries - parallel
  local first_question="${queries[0]#*:}"
  echo "Q: $first_question"
  echo ""

  local pids=()
  local temp_files=()
  local session_ids=()

  # Start all in parallel
  for i in "${!queries[@]}"; do
    local query="${queries[$i]}"
    local session_id="${query%%:*}"
    local question="${query#*:}"
    local temp_file="/tmp/memory-$$-$i.txt"
    temp_files+=("$temp_file")
    session_ids+=("$session_id")

    (recall_session "$session_id" "$question") > "$temp_file" 2>&1 &
    pids+=($!)
  done

  # Wait with timeout
  local elapsed=0
  while [ $elapsed -lt $timeout ]; do
    local all_done=true
    for pid in "${pids[@]}"; do
      if kill -0 "$pid" 2>/dev/null; then
        all_done=false
        break
      fi
    done
    $all_done && break
    sleep 1
    ((elapsed++))
  done

  # Kill remaining
  for pid in "${pids[@]}"; do
    kill -9 "$pid" 2>/dev/null || true
  done

  # Collect results
  local good_ids=()
  local good_contents=()
  local good_dates=()
  local no_info=0
  local errors=0

  for i in "${!temp_files[@]}"; do
    local temp_file="${temp_files[$i]}"
    local session_id="${session_ids[$i]}"

    if [ -f "$temp_file" ] && [ -s "$temp_file" ]; then
      local content=$(cat "$temp_file")
      if echo "$content" | grep -qiE "(I don't have (enough )?information|no information about)"; then
        ((no_info++))
      elif echo "$content" | grep -qiE "^Error:"; then
        ((errors++))
      else
        good_ids+=("${session_id:0:7}")
        good_contents+=("$content")
        good_dates+=("$(get_session_date "$session_id")")
      fi
    else
      ((errors++))
    fi
  done

  # Output results
  local total_good=${#good_ids[@]}
  if [ $total_good -gt 0 ]; then
    for i in "${!good_ids[@]}"; do
      echo "[$((i+1))/$total_good] ${good_ids[$i]} • ${good_dates[$i]}"
      echo "${good_contents[$i]}"
      echo ""
    done
    [ $no_info -gt 0 ] || [ $errors -gt 0 ] && echo "($no_info no info, $errors errors)" >&2
  else
    echo "RECALL_FALLBACK"
  fi

  rm -f "${temp_files[@]}"
}

# Main - only batch_recall, no standalone command
[ $# -eq 0 ] && { echo "Internal module. Use: memory search \"x\" --recall \"question\"" >&2; exit 1; }
batch_recall "$@"
