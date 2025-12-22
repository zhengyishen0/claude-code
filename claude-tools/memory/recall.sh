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

# Recall a single session (verbose mode)
recall_session() {
  local session_id="$1"
  local question="$2"
  local force_new="${3:-false}"

  # Get project directory from index
  local project_dir=$(get_project_from_index "$session_id")
  if [ -z "$project_dir" ] || [ ! -d "$project_dir" ]; then
    echo "Error: Session not found in index or project missing: $session_id" >&2
    echo "Run 'memory search' first to build/update the index" >&2
    return 1
  fi

  echo "Session: $session_id"
  echo "Project: $project_dir"
  echo "Question: $question"

  # Check for existing fork (unless --new)
  local fork_id=""
  if [ "$force_new" != "true" ]; then
    fork_id=$(get_fork_id "$session_id")
  fi

  if [ -n "$fork_id" ]; then
    echo "Reusing fork: $fork_id"
    echo ""
    (cd "$project_dir" && claude --resume "$fork_id" -p "$question" --allowedTools "Read,Grep,Glob" --model haiku)
  else
    echo "Creating new fork..."
    echo ""

    # Create fork with JSON output to capture new session ID
    local output
    output=$(cd "$project_dir" && claude --resume "$session_id" --fork-session -p "$question" --output-format json --allowedTools "Read,Grep,Glob" --model haiku 2>/dev/null)

    # Extract and display the result text
    local result_text=$(echo "$output" | jq -r '.result // empty')
    if [ -n "$result_text" ]; then
      echo "$result_text"
    fi

    # Extract and save fork session ID
    local new_fork_id=$(echo "$output" | jq -r '.session_id // empty')
    if [ -n "$new_fork_id" ]; then
      save_fork_id "$session_id" "$new_fork_id"
      echo ""
      echo "Fork saved: $new_fork_id"
    fi
  fi
}

# Batch recall with parallel execution
batch_recall() {
  local force_new="false"
  local queries=()

  # Parse args
  for arg in "$@"; do
    case "$arg" in
      --new|-n)
        force_new="true"
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
    # Single query - run directly
    local query="${queries[0]}"
    local session_id="${query%%:*}"
    local question="${query#*:}"
    recall_session "$session_id" "$question" "$force_new"
  else
    # Multiple queries - run in parallel
    echo "=== Batch Recall: $total sessions (parallel) ==="
    echo ""

    local pids=()
    local temp_files=()
    local index=0

    for query in "${queries[@]}"; do
      ((index++))
      local session_id="${query%%:*}"
      local question="${query#*:}"
      local temp_file="/tmp/memory-batch-$$-$index.txt"
      temp_files+=("$temp_file")

      (
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "[$index/$total] Session: $session_id"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        recall_session "$session_id" "$question" "$force_new" 2>&1
      ) > "$temp_file" 2>&1 &

      pids+=($!)
    done

    # Wait for all
    wait "${pids[@]}"

    # Print results in order
    for temp_file in "${temp_files[@]}"; do
      if [ -f "$temp_file" ]; then
        cat "$temp_file"
        echo ""
      fi
    done

    echo "=== All $total queries complete ==="
    rm -f "${temp_files[@]}"
  fi
}

# Main
case "${1:-}" in
  --help|-h|help)
    echo "Usage: memory recall [--new] \"<session-id>:<question>\" [...]"
    echo "Run 'memory --help' for full documentation"
    ;;
  *)
    [ $# -eq 0 ] && { echo "Usage: memory recall \"<session-id>:<question>\"" >&2; echo "Run 'memory --help' for full documentation" >&2; exit 1; }
    batch_recall "$@"
    ;;
esac
