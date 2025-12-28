#!/bin/bash
# Recall sessions by forking and asking questions
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INDEX_FILE="$HOME/.claude/memory-index.tsv"
CLAUDE_FAST="/Users/zhengyishen/.local/bin/claude-fast"

# Use gdate if available (brew install coreutils), otherwise use date
if command -v gdate >/dev/null 2>&1; then
  get_time_ms() { gdate +%s%3N; }
else
  # Fallback: use Python for millisecond precision
  get_time_ms() { python3 -c "import time; print(int(time.time() * 1000))"; }
fi

# Get project directory from index (5th column)
# Index format: session_id \t timestamp \t type \t text \t project_path
get_project_from_index() {
  local session_id="$1"
  grep "^$session_id" "$INDEX_FILE" 2>/dev/null | head -1 | cut -f5
}

# Get session date from index (2nd column)
get_session_date() {
  local session_id="$1"
  local timestamp=$(grep "^$session_id" "$INDEX_FILE" 2>/dev/null | head -1 | cut -f2)
  # Extract date part (YYYY-MM-DD) and reformat to "MMM DD"
  echo "$timestamp" | cut -d'T' -f1 | awk -F'-' '{
    months["01"]="Jan"; months["02"]="Feb"; months["03"]="Mar"; months["04"]="Apr";
    months["05"]="May"; months["06"]="Jun"; months["07"]="Jul"; months["08"]="Aug";
    months["09"]="Sep"; months["10"]="Oct"; months["11"]="Nov"; months["12"]="Dec";
    print months[$2] " " int($3)
  }'
}

# Recall a single session (compact mode)
recall_session() {
  local session_id="$1"
  local question="$2"
  local show_timing="${3:-false}"

  # Timing: Start overhead measurement
  local start_overhead=$(get_time_ms)

  # Get project directory from index
  local project_dir=$(get_project_from_index "$session_id")
  if [ -z "$project_dir" ] || [ ! -d "$project_dir" ]; then
    echo "Error: Session not found in index or project missing: $session_id" >&2
    echo "Run 'memory search' first to build/update the index" >&2
    return 1
  fi

  # Wrap question with format instructions
  local formatted_prompt="Answer the question concisely in this format:

[First line: One sentence summarizing the core idea]

• [Bullet point with key detail 1]
• [Bullet point with key detail 2]
• [Bullet point with key detail 3]
• [Additional bullets if essential, max 5 total]

Rules:
- First line MUST be a complete sentence (no label like \"ANSWER:\" or \"REASON:\")
- Each bullet point = one fact/comparison/metric
- Include numbers/metrics when relevant
- Keep total response under 150 tokens
- No tables, no headers, no markdown sections

IMPORTANT: If this session does NOT contain relevant information to answer the question, or if you are not confident about the answer, respond with ONLY:
\"I don't have information about that.\"

Do NOT attempt to answer if the information is not clearly present in this session.

Question: $question"

  # Timing: End overhead, start API call
  local end_overhead=$(get_time_ms)
  local start_api=$(get_time_ms)

  # Resume session with JSON output using claude-fast
  # claude-fast is 1.3-2x faster than normal claude (4-11s vs 8-13s)
  # Note: Adds recall Q&A to session history (not read-only)
  local output
  output=$("$CLAUDE_FAST" --model haiku --resume "$session_id" -p "$formatted_prompt" --output-format json --allowedTools "Read,Grep,Glob" 2>/dev/null)

  # Timing: End API call
  local end_api=$(get_time_ms)

  # Extract and display the result text only
  local result_text=$(echo "$output" | jq -r '.result // empty')
  if [ -n "$result_text" ]; then
    echo "$result_text"
  fi

  # Show timing if requested
  if [ "$show_timing" = "true" ]; then
    local overhead_ms=$((end_overhead - start_overhead))
    local api_ms=$((end_api - start_api))
    local total_ms=$((end_api - start_overhead))
    echo "" >&2
    echo "⏱ Timing:" >&2
    echo "  Overhead: ${overhead_ms}ms" >&2
    echo "  API call: ${api_ms}ms" >&2
    echo "  Total:    ${total_ms}ms" >&2
  fi
}

# Batch recall with parallel execution and timeout
batch_recall() {
  local queries=("$@")
  local total=${#queries[@]}
  local timeout=15000  # 15 second timeout in milliseconds

  if [ $total -eq 0 ]; then
    echo "Error: No queries provided" >&2
    return 1
  fi

  if [ $total -eq 1 ]; then
    # Single query - run directly (no header)
    local query="${queries[0]}"
    local session_id="${query%%:*}"
    local question="${query#*:}"
    recall_session "$session_id" "$question" "true"
  else
    # Multiple queries - run in parallel
    # First, show the question once at the top
    local first_query="${queries[0]}"
    local first_question="${first_query#*:}"
    echo "Q: $first_question"
    echo ""

    local pids=()
    local temp_files=()
    local session_ids=()
    local index=0

    # Timing: Start parallel batch
    local start_batch=$(get_time_ms)

    # Start all sessions in parallel
    for query in "${queries[@]}"; do
      ((index++))
      local session_id="${query%%:*}"
      local question="${query#*:}"
      local temp_file="/tmp/memory-batch-$$-$index.txt"
      temp_files+=("$temp_file")
      session_ids+=("$session_id")

      (
        local start_individual=$(get_time_ms)
        recall_session "$session_id" "$question" "false" 2>&1
        local end_individual=$(get_time_ms)
        local individual_ms=$((end_individual - start_individual))
        echo "" >&2
        echo "[Recall timing for $session_id: ${individual_ms}ms]" >&2
      ) > "$temp_file" 2>&1 &

      pids+=($!)
    done

    # Wait with timeout - kill slow processes after timeout
    local elapsed=0
    local check_interval=100  # Check every 100ms
    local all_done=false

    while [ $elapsed -lt $timeout ] && [ "$all_done" = false ]; do
      all_done=true
      for pid in "${pids[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
          all_done=false
          break
        fi
      done

      if [ "$all_done" = false ]; then
        sleep 0.1
        elapsed=$((elapsed + check_interval))
      fi
    done

    # Kill any remaining processes that exceeded timeout
    for pid in "${pids[@]}"; do
      if kill -0 "$pid" 2>/dev/null; then
        kill -9 "$pid" 2>/dev/null || true
      fi
    done

    # Timing: End parallel batch
    local end_batch=$(get_time_ms)
    local batch_ms=$((end_batch - start_batch))

    # Count different categories of responses
    index=0
    local no_info=0
    local timeout_error=0
    local good_session_ids=()
    local good_contents=()
    local good_dates=()

    for temp_file in "${temp_files[@]}"; do
      ((index++))
      local session_id="${session_ids[$((index-1))]}"
      local short_id="${session_id:0:7}"
      local session_date=$(get_session_date "$session_id")

      if [ -f "$temp_file" ] && [ -s "$temp_file" ]; then
        local content=$(cat "$temp_file")
        # Check if it's a "no info" response
        if echo "$content" | grep -qiE "(I don't have (enough )?information|Could you clarify|I'm not sure about|don't have.*(details|info)|cannot find|no information about|haven't researched)"; then
          ((no_info++))
        # Check if it's an error
        elif echo "$content" | grep -qiE "^Error:"; then
          ((timeout_error++))
        else
          # It's a good response - store for later display
          good_session_ids+=("$short_id")
          good_contents+=("$content")
          good_dates+=("$session_date")
        fi
      else
        # No output file or empty = timeout
        ((timeout_error++))
      fi
    done

    local total_good=${#good_session_ids[@]}

    # If we have good responses, show them with correct numbering
    if [ $total_good -gt 0 ]; then
      for i in "${!good_session_ids[@]}"; do
        local num=$((i + 1))
        echo "[$num/$total_good] ${good_session_ids[$i]} • ${good_dates[$i]}"
        echo "${good_contents[$i]}"
        echo ""
      done

      # Show summary of filtered sessions
      local summary_parts=()
      if [ $no_info -gt 0 ]; then
        summary_parts+=("$no_info no info")
      fi
      if [ $timeout_error -gt 0 ]; then
        summary_parts+=("$timeout_error timeout/error")
      fi

      if [ ${#summary_parts[@]} -gt 0 ]; then
        local summary=$(IFS=', '; echo "${summary_parts[*]}")
        echo "($summary)" >&2
      fi

      echo "⏱ Batch timing: ${batch_ms}ms for ${total} parallel recalls" >&2
    else
      # No good responses - signal fallback
      echo "RECALL_FALLBACK"
      echo "⏱ No relevant answers from recall (${batch_ms}ms, $no_info no info, $timeout_error timeout/error)" >&2
    fi

    rm -f "${temp_files[@]}"
  fi
}

# Main
case "${1:-}" in
  --help|-h|help)
    echo "Usage: memory recall \"<session-id>:<question>\" [...]"
    echo "Run 'memory --help' for full documentation"
    ;;
  *)
    [ $# -eq 0 ] && { echo "Usage: memory recall \"<session-id>:<question>\"" >&2; echo "Run 'memory --help' for full documentation" >&2; exit 1; }
    batch_recall "$@"
    ;;
esac
