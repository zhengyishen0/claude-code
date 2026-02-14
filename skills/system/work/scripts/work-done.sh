#!/usr/bin/env bash
# work done - Merge current workspace to main and clean up
# Usage: work done ["summary"]
set -euo pipefail

# Find workspace name from session ID or current directory
if [ -n "${CLAUDE_SESSION_ID:-}" ]; then
    ws="[${CLAUDE_SESSION_ID:0:8}]"
    summary="${1:-Merge ${ws}}"
else
    # Try to detect from current directory name
    ws="$(basename "$PWD")"
    if [[ "$ws" != "["*"]" ]]; then
        echo "Usage: work done [\"summary\"]"
        echo "  Run from workspace dir, or set CLAUDE_SESSION_ID"
        echo ""
        echo "Active workspaces:"
        jj workspace list
        exit 1
    fi
    summary="${1:-Merge ${ws}}"
fi

ws_path="$HOME/.workspace/${ws}"

if [ ! -d "$ws_path" ]; then
    echo "Workspace not found: $ws_path"
    exit 1
fi

# Read repo root saved by work-on
if [ ! -f "$ws_path/.repo_root" ]; then
    echo "Missing .repo_root file in workspace"
    exit 1
fi
repo_root=$(cat "$ws_path/.repo_root")

change=$(cd "$ws_path" && jj log -r @ --no-graph -T 'change_id.short()')

if [ -z "$change" ]; then
    echo "Could not find change ID in workspace"
    exit 1
fi

echo "Merging ${change} from ${ws}..."

cd "$repo_root" && \
jj new main "${change}" -m "${summary}" && \
jj bookmark set main -r @ && \
jj new && \
jj workspace forget "${ws}"

rm -rf "$ws_path" 2>/dev/null

echo "Merged and cleaned up"

# Show graph: recent commits
jj log -r "::@" -n 5
