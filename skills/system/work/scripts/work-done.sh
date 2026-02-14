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

# Create merge node with main and current work
jj new main "${change}" -m "[merge] ${summary}"
merge_rev=$(jj log -r @ --no-graph -T 'change_id.short()')

# Move main bookmark to merge
jj bookmark set main -r @

# Ensure [PROTECTED] exists as child of main, move default@ there
protected_rev=$(get_protected_rev)
if [[ -n "$protected_rev" ]]; then
    # Rebase existing [PROTECTED] onto new main
    jj rebase -r "$protected_rev" -d main
else
    # Create new [PROTECTED]
    jj new main -m "[PROTECTED] do not edit — use \`work on\`"
    protected_rev=$(jj log -r @ --no-graph -T 'change_id.short()')
fi

# default@ is in repo_root, move it to [PROTECTED]
cd "$repo_root" && jj edit "$protected_rev"

# Move ws@ to merge (main)
cd "$ws_path" && jj edit "$merge_rev"

echo "Merged. Ready for next task."
jj log -r @ --limit 1
