#!/usr/bin/env bash
# cc.sh - Claude Code wrapper with fuzzy session continue
#
# Usage:
#   cc                     # Start new session
#   cc --continue <partial> # Resume session matching partial ID
#   cc -c <partial>        # Short form
#   cc <other args>        # Pass through to claude

set -euo pipefail

: "${PROJECT_DIR:=$HOME/Codes/claude-code}"

# Check for --continue or -c flag
if [[ "${1:-}" == "--resume" || "${1:-}" == "-r" ]]; then
    partial="${2:-}"
    
    if [[ -z "$partial" ]]; then
        echo "Error: --resume requires a partial session ID" >&2
        echo "Usage: cc --resume <partial-id>" >&2
        exit 1
    fi

    session_id=""

    # 1. Search Claude session files (primary source)
    # Get current project path for session lookup
    current_project=$(pwd | sed 's|/|_|g; s|^_|-|')
    claude_sessions_dir="$HOME/.claude/projects/$current_project"

    if [[ -d "$claude_sessions_dir" ]]; then
        matches=$(ls -t "$claude_sessions_dir"/*.jsonl 2>/dev/null | xargs -I{} basename {} .jsonl | grep -i "$partial" || true)
        if [[ -n "$matches" ]]; then
            match_count=$(echo "$matches" | wc -l | tr -d ' ')
            if [[ "$match_count" -gt 1 ]]; then
                echo "Multiple Claude sessions match '$partial':" >&2
                echo "$matches" | head -10 | while read -r m; do
                    # Show date from file
                    file="$claude_sessions_dir/$m.jsonl"
                    date=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$file" 2>/dev/null || echo "?")
                    size=$(stat -f "%z" "$file" 2>/dev/null | awk '{printf "%.0fk", $1/1024}')
                    echo "  $m ($date, $size)" >&2
                done
                [[ "$match_count" -gt 10 ]] && echo "  ... and $((match_count - 10)) more" >&2
                echo "" >&2
                echo "Be more specific." >&2
                exit 1
            fi
            session_id=$(echo "$matches" | head -1)
        fi
    fi

    # 2. Search all Claude projects if not found in current
    if [[ -z "$session_id" ]]; then
        matches=$(find "$HOME/.claude/projects" -name "*.jsonl" -type f 2>/dev/null | \
            xargs -I{} basename {} .jsonl | grep -i "$partial" | sort -u || true)
        if [[ -n "$matches" ]]; then
            match_count=$(echo "$matches" | wc -l | tr -d ' ')
            if [[ "$match_count" -gt 1 ]]; then
                echo "Multiple Claude sessions match '$partial' (across all projects):" >&2
                echo "$matches" | head -10 | sed 's/^/  /' >&2
                [[ "$match_count" -gt 10 ]] && echo "  ... and $((match_count - 10)) more" >&2
                echo "" >&2
                echo "Be more specific." >&2
                exit 1
            fi
            session_id=$(echo "$matches" | head -1)
        fi
    fi

    # 3. Fallback: search jj workspaces
    if [[ -z "$session_id" ]]; then
        matches=$(jj workspace list 2>/dev/null | grep -i "$partial" | awk -F: '{print $1}' || true)
        if [[ -n "$matches" ]]; then
            match_count=$(echo "$matches" | wc -l | tr -d ' ')
            if [[ "$match_count" -gt 1 ]]; then
                echo "Multiple jj workspaces match '$partial':" >&2
                echo "$matches" | sed 's/^/  /' >&2
                echo "" >&2
                echo "Be more specific." >&2
                exit 1
            fi
            workspace_name=$(echo "$matches" | head -1)
            # Extract session ID from workspace name
            session_id="${workspace_name%%-*}"
            # Try to find full UUID
            full_session=$(find "$HOME/.claude" -maxdepth 3 -type d -name "${session_id}*" 2>/dev/null | head -1 || true)
            [[ -n "$full_session" ]] && session_id=$(basename "$full_session")
        fi
    fi

    if [[ -z "$session_id" ]]; then
        echo "Error: No session found matching '$partial'" >&2
        echo "" >&2
        echo "Recent sessions in current project:" >&2
        if [[ -d "$claude_sessions_dir" ]]; then
            ls -t "$claude_sessions_dir"/*.jsonl 2>/dev/null | head -5 | while read -r f; do
                name=$(basename "$f" .jsonl)
                date=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$f" 2>/dev/null || echo "?")
                echo "  ${name:0:8}... ($date)" >&2
            done
        else
            echo "  (no sessions found)" >&2
        fi
        exit 1
    fi

    echo "Resuming session: $session_id" >&2
    shift 2
    exec claude --resume "$session_id" --dangerously-skip-permissions --model "claude-opus-4-5" "$@"
else
    # Pass through to claude
    COLUMNS=200 exec claude --dangerously-skip-permissions --model "claude-opus-4-5" "$@"
fi
