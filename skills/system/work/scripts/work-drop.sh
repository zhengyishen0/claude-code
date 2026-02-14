#!/usr/bin/env bash
# work drop - Abandon current workspace without merging
# Usage: work drop
set -euo pipefail

# Workspace path from env (set by spawn) or current directory
ws_path="${ZENIX_WORKSPACE_PATH:-$PWD}"
ws_name=$(basename "$ws_path")    # cc-a1b2c3d4

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

echo "Dropping workspace ${ws_name}..."

# Forget workspace (change becomes orphaned, not abandoned)
cd "$repo_root" && jj workspace forget "${ws_name}"

rm -rf "$ws_path" 2>/dev/null

echo "Dropped (change orphaned, not abandoned)"
