#!/usr/bin/env bash
# vcs done - Merge current workspace to main and clean up
# Usage: vcs done ["summary"]
set -euo pipefail

# Find workspace name: explicit arg, or from session ID, or detect from cwd
if [ -n "${1:-}" ] && [[ "$1" == "["* ]]; then
    ws="$1"
    summary="${2:-Merge ${ws}}"
elif [ -n "${CLAUDE_SESSION_ID:-}" ]; then
    ws="[${CLAUDE_SESSION_ID:0:8}]"
    summary="${1:-Merge ${ws}}"
else
    # Try to detect from current directory name
    ws="$(basename "$PWD")"
    if [[ "$ws" != "["*"]" ]]; then
        echo "Usage: vcs done [\"summary\"]"
        echo "  Run from workspace dir, or set CLAUDE_SESSION_ID"
        echo ""
        echo "Active workspaces:"
        jj workspace list
        exit 1
    fi
    summary="${1:-Merge ${ws}}"
fi

ws_path="$(dirname ~/.zenix)/${ws}"

if [ ! -d "$ws_path" ]; then
    echo "Workspace not found: $ws_path"
    exit 1
fi

change=$(cd "$ws_path" && jj log -r @ --no-graph -T 'change_id.short()')

if [ -z "$change" ]; then
    echo "Could not find change ID in workspace"
    exit 1
fi

echo "Merging ${change} from ${ws}..."

cd ~/.zenix && \
jj new main "${change}" -m "${summary}" && \
jj bookmark set main -r @ && \
jj workspace forget "${ws}"

rm -rf "$ws_path" 2>/dev/null

echo "Merged and cleaned up"
