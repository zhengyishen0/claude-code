#!/usr/bin/env bash
# work done - Merge current node to main, keep workspace for next task
# Usage: work done ["summary"]
set -euo pipefail

# Workspace path from env (set by spawn) or current directory
ws_path="${ZENIX_WORKSPACE_PATH:-$PWD}"
ws_name=$(basename "$ws_path")    # cc-a1b2c3d4
tag="[${ws_name}]"                # [cc-a1b2c3d4]
summary="${1:-Merge ${tag}}"

# Validate workspace
if [[ ! "$ws_name" =~ ^[a-z]+-[a-f0-9]+$ ]]; then
    echo "Not in a workspace. Set ZENIX_WORKSPACE_PATH or cd to workspace." >&2
    exit 1
fi

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

cd "$repo_root"

# Merge behind [PROTECTED]: parent of main + workspace change
jj new "main^" "${change}" -m "[merge] ${summary}"

# Move [PROTECTED] to tip
jj rebase -r main -d @

# Repo @ stays on [PROTECTED]
jj edit main

# Sync workspace to [PROTECTED]
cd "$ws_path" && jj edit main

echo "Merged. Ready for next task."

# Show graph
jj log -r "main^..main" -n 5
