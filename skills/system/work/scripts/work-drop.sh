#!/usr/bin/env bash
# work drop - Abandon current workspace without merging
# Usage: work drop
set -euo pipefail

: "${ZENIX_WORKSPACE:=$HOME/.workspace}"

# Find workspace name from session ID or current directory
if [ -n "${CLAUDE_SESSION_ID:-}" ]; then
    ws="[${CLAUDE_SESSION_ID:0:8}]"
else
    # Try to detect from current directory name
    ws="$(basename "$PWD")"
    if [[ "$ws" != "["*"]" ]]; then
        echo "Usage: work drop"
        echo "  Run from workspace dir, or set CLAUDE_SESSION_ID"
        echo ""
        echo "Active workspaces:"
        jj workspace list
        exit 1
    fi
fi

ws_path="$ZENIX_WORKSPACE/${ws}"

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

echo "Dropping workspace ${ws}..."

# Forget workspace (change becomes orphaned, not abandoned)
cd "$repo_root" && jj workspace forget "${ws}"

rm -rf "$ws_path" 2>/dev/null

echo "Dropped (change orphaned, not abandoned)"
