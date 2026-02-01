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
if [[ "${1:-}" == "--continue" || "${1:-}" == "-c" ]]; then
    partial="${2:-}"
    
    if [[ -z "$partial" ]]; then
        echo "Error: --continue requires a partial session ID" >&2
        echo "Usage: cc --continue <partial-id>" >&2
        exit 1
    fi
    
    # Search for matching session in jj workspaces
    matches=$(jj workspace list 2>/dev/null | grep -i "$partial" | awk -F: '{print $1}' || true)
    
    if [[ -z "$matches" ]]; then
        # Try searching in jj log descriptions
        matches=$(jj log -r 'all()' --no-graph -T 'description ++ "\n"' 2>/dev/null | \
            grep -oE '\([a-f0-9]{8}\)' | tr -d '()' | grep -i "$partial" | head -1 || true)
    fi
    
    if [[ -z "$matches" ]]; then
        echo "Error: No session found matching '$partial'" >&2
        echo "" >&2
        echo "Active workspaces:" >&2
        jj workspace list 2>/dev/null | grep -v '^default:' || echo "  (none)"
        exit 1
    fi
    
    # If multiple matches, show them
    match_count=$(echo "$matches" | wc -l | tr -d ' ')
    if [[ "$match_count" -gt 1 ]]; then
        echo "Multiple sessions match '$partial':" >&2
        echo "$matches" | sed 's/^/  /' >&2
        echo "" >&2
        echo "Be more specific." >&2
        exit 1
    fi
    
    # Extract session ID from workspace name (format: <session-id>-<task-name>)
    workspace_name=$(echo "$matches" | head -1)
    session_id="${workspace_name%%-*}"
    
    # Find full session ID by searching .claude directory
    full_session=$(find "$HOME/.claude" -maxdepth 3 -type d -name "${session_id}*" 2>/dev/null | head -1 || true)
    
    if [[ -n "$full_session" ]]; then
        session_id=$(basename "$full_session")
    fi
    
    echo "Resuming session: $session_id" >&2
    shift 2
    exec claude --continue "$session_id" "$@"
else
    # Pass through to claude
    COLUMNS=200 exec claude --dangerously-skip-permissions "$@"
fi
