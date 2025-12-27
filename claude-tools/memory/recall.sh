#!/bin/bash
# Recall sessions by forking and asking questions
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MEMORY_STATE_DIR="$HOME/.claude/memory-state"
INDEX_FILE="$HOME/.claude/memory-index.tsv"

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

# Get fork session ID for a session
get_fork_id() {
  local session_id="$1"
  local state_file="$MEMORY_STATE_DIR/$session_id.fork"

  if [ -f "$state_file" ]; then
    cat "$state_file"
  fi
}

# Save fork session ID
save_fork_id() {
  local session_id="$1"
  local fork_id="$2"

  mkdir -p "$MEMORY_STATE_DIR"
  echo "$fork_id" > "$MEMORY_STATE_DIR/$session_id.fork"
}

# Shorten path (replace $HOME with ~)
shorten_path() {
  echo "$1" | sed "s|^$HOME|~|"
}

# Recall a single session (compact mode)
recall_session() {
  local session_id="$1"
  local question="$2"
  local resume_fork="${3:-false}"

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

Question: $question"

  # Check for existing fork (only if --resume)
  local fork_id=""
  if [ "$resume_fork" = "true" ]; then
    fork_id=$(get_fork_id "$session_id")
  fi

  if [ -n "$fork_id" ]; then
    # Resume existing fork (silent)
    (cd "$project_dir" && claude --resume "$fork_id" -p "$formatted_prompt" --allowedTools "Read,Grep,Glob" --model haiku 2>/dev/null)
  else
    # Create fork with JSON output to capture new session ID
    local output
    output=$(cd "$project_dir" && claude --resume "$session_id" --fork-session -p "$formatted_prompt" --output-format json --allowedTools "Read,Grep,Glob" --model haiku 2>/dev/null)

    # Extract and display the result text only
    local result_text=$(echo "$output" | jq -r '.result // empty')
    if [ -n "$result_text" ]; then
      echo "$result_text"
    fi

    # Save fork session ID silently
    local new_fork_id=$(echo "$output" | jq -r '.session_id // empty')
    if [ -n "$new_fork_id" ]; then
      save_fork_id "$session_id" "$new_fork_id"
    fi
  fi
}

# Batch recall with parallel execution
batch_recall() {
  local resume_fork="false"
  local queries=()

  # Parse args
  for arg in "$@"; do
    case "$arg" in
      --resume|-r)
        resume_fork="true"
        ;;
      *)
        queries+=("$arg")
        ;;
    esac
  done

  local total=${#queries[@]}

  if [ $total -eq 0 ]; then
    echo "Error: No queries provided" >&2
    return 1
  fi

  if [ $total -eq 1 ]; then
    # Single query - run directly (no header)
    local query="${queries[0]}"
    local session_id="${query%%:*}"
    local question="${query#*:}"
    recall_session "$session_id" "$question" "$resume_fork"
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

    # Start all sessions in parallel
    for query in "${queries[@]}"; do
      ((index++))
      local session_id="${query%%:*}"
      local question="${query#*:}"
      local temp_file="/tmp/memory-batch-$$-$index.txt"
      temp_files+=("$temp_file")
      session_ids+=("$session_id")

      (
        recall_session "$session_id" "$question" "$resume_fork" 2>&1
      ) > "$temp_file" 2>&1 &

      pids+=($!)
    done

    # Wait for all
    wait "${pids[@]}"

    # Print results in order with compact headers, filtering out "no info" responses
    index=0
    local shown=0
    for temp_file in "${temp_files[@]}"; do
      ((index++))
      local session_id="${session_ids[$((index-1))]}"
      local short_id="${session_id:0:7}"
      local session_date=$(get_session_date "$session_id")

      if [ -f "$temp_file" ]; then
        local content=$(cat "$temp_file")
        # Skip responses indicating no useful information
        if echo "$content" | grep -qiE "(I don't have (enough )?information|Could you clarify|I'm not sure about|don't have.*(details|info)|cannot find|no information about|haven't researched)"; then
          continue
        fi
        ((shown++))
        echo "[$shown/$total] $short_id • $session_date"
        echo "$content"
        echo ""
      fi
    done

    rm -f "${temp_files[@]}"
  fi
}

# Main
case "${1:-}" in
  --help|-h|help)
    echo "Usage: memory recall [--resume] \"<session-id>:<question>\" [...]"
    echo "Run 'memory --help' for full documentation"
    ;;
  *)
    [ $# -eq 0 ] && { echo "Usage: memory recall \"<session-id>:<question>\"" >&2; echo "Run 'memory --help' for full documentation" >&2; exit 1; }
    batch_recall "$@"
    ;;
esac
