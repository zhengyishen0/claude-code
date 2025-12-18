#!/bin/bash
# Recall sessions by forking and asking questions
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MEMORY_STATE_DIR="$HOME/.claude/memory-state"

# Find session file across all projects
find_session_file() {
  local session_id="$1"
  find "$HOME/.claude/projects" -name "$session_id.jsonl" -type f 2>/dev/null | head -1
}

# Get project directory from session file path
# ~/.claude/projects/-Users-foo-bar/session.jsonl -> /Users/foo/bar
# Strategy: try combining remaining segments when slash doesn't work
get_project_dir() {
  local session_file="$1"
  local project_dir=$(dirname "$session_file")
  local project_name=$(basename "$project_dir")
  local cleaned=$(echo "$project_name" | sed 's/^-//')

  IFS="-" read -ra parts <<< "$cleaned"
  local n=${#parts[@]}
  local current="/${parts[0]}"

  for ((i=1; i<n; i++)); do
    local with_slash="$current/${parts[i]}"

    if [ -d "$with_slash" ]; then
      current="$with_slash"
    else
      # Try combining remaining parts as a single directory name
      local combined=""
      for ((j=i; j<n; j++)); do
        if [ -z "$combined" ]; then
          combined="${parts[j]}"
        else
          combined="$combined-${parts[j]}"
        fi
      done
      local try_combined="$current/$combined"
      if [ -d "$try_combined" ]; then
        current="$try_combined"
        break
      else
        # No luck - just use slash and continue
        current="$with_slash"
      fi
    fi
  done

  echo "$current"
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

# Recall a single session
recall_session() {
  local session_id="$1"
  local question="$2"
  local force_new="${3:-false}"
  local model="${4:-haiku}"

  # Find the session file
  local session_file=$(find_session_file "$session_id")
  if [ -z "$session_file" ]; then
    echo "Error: Session not found: $session_id" >&2
    return 1
  fi

  # Get project directory to run claude from correct location
  local project_dir=$(get_project_dir "$session_file")
  if [ ! -d "$project_dir" ]; then
    echo "Warning: Project directory not found: $project_dir" >&2
    project_dir="$HOME"  # Fallback to home
  fi

  echo "Session: $session_id"
  echo "Project: $project_dir"
  echo "Model: $model"
  echo "Question: $question"

  # Check for existing fork (unless --new)
  local fork_id=""
  if [ "$force_new" != "true" ]; then
    fork_id=$(get_fork_id "$session_id")
  fi

  if [ -n "$fork_id" ]; then
    echo "Reusing fork: $fork_id"
    echo ""
    (cd "$project_dir" && claude --resume "$fork_id" -p "$question" --model "$model" --allowedTools "Read,Grep,Glob" --dangerously-skip-permissions)
  else
    echo "Creating new fork..."
    echo ""

    # Create fork and run claude directly (don't capture - let it stream output)
    (cd "$project_dir" && claude --resume "$session_id" --fork-session -p "$question" --model "$model" --allowedTools "Read,Grep,Glob" --dangerously-skip-permissions)

    # Try to find the new fork session ID
    sleep 1  # Give filesystem time to sync
    local newest=$(find "$HOME/.claude/projects" -name "*.jsonl" -type f -mmin -1 -not -name "$session_id.jsonl" 2>/dev/null | head -1)
    if [ -n "$newest" ]; then
      local new_fork_id=$(basename "$newest" .jsonl)
      save_fork_id "$session_id" "$new_fork_id"
      echo ""
      echo "Fork saved. Follow-up questions will reuse this fork."
    fi
  fi
}

# Batch recall with parallel execution
batch_recall() {
  local force_new="false"
  local model="haiku"
  local queries=()

  # Parse args
  for arg in "$@"; do
    case "$arg" in
      --new|-n)
        force_new="true"
        ;;
      --model=*)
        model="${arg#--model=}"
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
    recall_session "$session_id" "$question" "$force_new" "$model"
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
        recall_session "$session_id" "$question" "$force_new" "$model" 2>&1
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

# Show help
show_help() {
  cat << 'EOF'
recall - Consult past sessions by forking and asking questions

USAGE
  recall [OPTIONS] "<session-id>:<question>" [...]

OPTIONS
  --new, -n           Force new fork (ignore existing)
  --model=MODEL       Model to use (default: haiku)
                      Options: haiku, sonnet, opus

EXAMPLES
  # Single query (uses haiku by default)
  recall "abc-123:How did you handle errors?"

  # Force new fork
  recall --new "abc-123:Start fresh question"

  # Use a different model
  recall --model=sonnet "abc-123:Complex reasoning question"

  # Multiple queries (parallel)
  recall "session1:question1" "session2:question2"

NOTES
  - First query to a session creates a fork
  - Follow-up questions reuse the same fork
  - Use --new to start fresh
  - Haiku is recommended for most recall tasks (faster, cheaper)
EOF
}

# Main
case "${1:-}" in
  --help|-h|help)
    show_help
    ;;
  *)
    [ $# -eq 0 ] && { show_help; exit 1; }
    batch_recall "$@"
    ;;
esac
