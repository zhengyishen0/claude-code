#!/usr/bin/env bash
# work done - Merge current node to main, keep workspace for next task
# Usage: work done ["summary"]
set -euo pipefail

source "$(dirname "$0")/../lib/protected.sh"

ws_path="${ZENIX_WORKSPACE_PATH:-$PWD}"
ws_name=$(basename "$ws_path")
tag="[${ws_name}]"
summary="${1:-Merge ${tag}}"

# Validate workspace
if [[ ! "$ws_name" =~ ^[a-z]+-[a-f0-9]+$ ]]; then
    echo "Not in a workspace. Set ZENIX_WORKSPACE_PATH or cd to workspace." >&2
    exit 1
fi

if [ ! -d "$ws_path" ]; then
    echo "Workspace not found: $ws_path" >&2
    exit 1
fi

repo_root=$(cat "$ws_path/.repo_root" 2>/dev/null)
if [ -z "$repo_root" ]; then
    echo "Missing .repo_root file in workspace" >&2
    exit 1
fi

change=$(cd "$ws_path" && jj log -r @ --no-graph -T 'change_id.short()')
if [ -z "$change" ]; then
    echo "Could not find change ID in workspace" >&2
    exit 1
fi

echo "Merging ${change} from ${ws_name}..."

cd "$repo_root"

if main_is_protected; then
    # Main is [PROTECTED]: merge behind it, rebase to tip
    jj new "main-" "${change}" -m "[merge] ${summary}"
    jj rebase -r main -d @
else
    # Main is not [PROTECTED]: merge, then create [PROTECTED]
    jj new main "${change}" -m "[merge] ${summary}"
    jj bookmark set main -r @
    jj new -m "[PROTECTED] do not edit — use \`work on\`"
    jj bookmark set main -r @
fi

# Sync both @ to [PROTECTED]
jj edit main
cd "$ws_path" && jj edit main

echo "Merged. Ready for next task."
jj log -r "main-..main" -n 5
