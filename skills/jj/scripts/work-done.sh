#!/usr/bin/env bash
# work-done - Merge a jj workspace to main and clean up
# Usage: work done "workspace-name" ["summary"]
set -euo pipefail

ws="$1"
summary="${2:-Merge ${ws}}"

if [ -z "$ws" ]; then
    echo "Usage: work done \"workspace-name\" [\"summary\"]"
    echo ""
    echo "Active workspaces:"
    jj workspace list
    exit 1
fi

ws_path="$HOME/.workspaces/claude-code/${ws}"

if [ ! -d "$ws_path" ]; then
    echo "Workspace not found: $ws_path"
    exit 1
fi

change=$(cd "$ws_path" && jj log -r @ --no-graph -T 'change_id.short()')

if [ -z "$change" ]; then
    echo "Could not find change ID in workspace"
    exit 1
fi

echo "Merging change ${change} from ${ws}..."

cd ~/.claude-code && \
jj new main "${change}" -m "${summary}" && \
jj bookmark set main -r @ && \
jj workspace forget "${ws}"

# Clean up workspace directory
rm -rf "$ws_path" 2>/dev/null

echo ""
echo "Merged and cleaned up"
