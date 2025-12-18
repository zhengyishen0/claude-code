#!/bin/bash
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

# Get fork session ID for an expert session
get_fork_id() {
  local expert_id="$1"
  local state_file="$MEMORY_STATE_DIR/$expert_id.fork"

  if [ -f "$state_file" ]; then
    cat "$state_file"
  fi
}

# Save fork session ID for an expert session
save_fork_id() {
  local expert_id="$1"
  local fork_id="$2"

  mkdir -p "$MEMORY_STATE_DIR"
  echo "$fork_id" > "$MEMORY_STATE_DIR/$expert_id.fork"
}

# Recall session (with fork tracking for follow-ups)
recall_session() {
  local session_id="$1"
  local question="$2"
  local force_new="${3:-false}"

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
  echo "Question: $question"

  # Check for existing fork (unless --new)
  local fork_id=""
  if [ "$force_new" != "true" ]; then
    fork_id=$(get_fork_id "$session_id")
  fi

  if [ -n "$fork_id" ]; then
    echo "Reusing fork: $fork_id"
    echo ""
    (cd "$project_dir" && claude --resume "$fork_id" -p "$question" --allowedTools "Read,Grep,Glob" --dangerously-skip-permissions)
  else
    echo "Creating new fork..."
    echo ""

    # Create fork and capture output (--resume with session ID + --fork-session)
    # Run from project directory so claude can find the session
    local output=$(cd "$project_dir" && claude --resume "$session_id" --fork-session -p "$question" --allowedTools "Read,Grep,Glob" --dangerously-skip-permissions 2>&1)
    echo "$output"

    # Try to find the new fork session ID
    # Look for most recent session file created after we started
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
  local queries=()

  # Parse args
  for arg in "$@"; do
    if [ "$arg" = "--new" ] || [ "$arg" = "-n" ]; then
      force_new="true"
    else
      queries+=("$arg")
    fi
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

# Show help
show_help() {
  cat << 'EOF'
memory - Cross-session knowledge sharing for Claude Code

USAGE
  claude-tools memory search "<query>"
  claude-tools memory recall [--new] "<session-id>:<question>" [...]

COMMANDS
  search "<query>"
      Search all sessions with boolean logic.

      Query syntax:
        term1|term2    OR  (first term, rg pattern)
        term           AND (space-separated)
        -term          NOT (dash prefix)

      Examples:
        memory search "error"
        memory search "chrome|playwright"
        memory search "chrome|playwright click -test"

  recall [--new] "<session-id>:<question>" [...]
      Consult a session by forking it and asking a question.

      Flags:
        --new, -n    Force new fork (ignore existing)

      Examples:
        # Single query
        memory recall "abc-123:How did you handle errors?"

        # Force new fork
        memory recall --new "abc-123:Start fresh question"

        # Multiple queries (parallel)
        memory recall "session1:question1" "session2:question2"

WORKFLOW
  1. Search for relevant sessions:
     $ claude-tools memory search "authentication"

  2. Pick a session from results and ask questions:
     $ claude-tools memory recall "abc-123:How did you implement JWT?"

  3. Follow-up questions reuse the same fork:
     $ claude-tools memory recall "abc-123:What about refresh tokens?"

  4. Start fresh when needed:
     $ claude-tools memory recall --new "abc-123:Different topic"

TECHNICAL NOTES
  - Index: ~/.claude/memory-index.tsv
  - Fork state: ~/.claude/memory-state/<session-id>.fork
  - First search builds index (~12s), subsequent searches ~0.5s

REQUIREMENTS
  - ripgrep (rg)
  - jq
  - Claude Code CLI

EOF
}

# Main command router
case "${1:-}" in
  search)
    [ $# -lt 2 ] && { echo "Usage: memory search \"<query>\"" >&2; exit 1; }
    "$SCRIPT_DIR/search.sh" "$2"
    ;;

  recall)
    shift
    [ $# -eq 0 ] && { echo "Usage: memory recall [--new] \"<session-id>:<question>\" [...]" >&2; exit 1; }
    batch_recall "$@"
    ;;

  --help|-h|help|"")
    show_help
    ;;

  *)
    echo "Unknown command: $1" >&2
    echo "Run 'claude-tools memory --help' for usage" >&2
    exit 1
    ;;
esac
