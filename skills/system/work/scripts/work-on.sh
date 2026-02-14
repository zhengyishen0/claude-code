#!/usr/bin/env bash
# work on - Attach to workspace and create a new node for task
# Usage: cd "$(work on 'task')"
set -euo pipefail

source "$(dirname "$0")/../lib/protected.sh"

task="${1:-}"
if [ -z "$task" ]; then
    echo "Usage: work on \"task description\"" >&2
    exit 1
fi

# Workspace path from env (set by spawn) or current directory
ws_path="${ZENIX_WORKSPACE_PATH:-$PWD}"
ws_name=$(basename "$ws_path")
tag="[${ws_name}]"

# Validate workspace name pattern
if [[ ! "$ws_name" =~ ^[a-z]+-[a-f0-9]+$ ]]; then
    echo "Not in a workspace. Set ZENIX_WORKSPACE_PATH or cd to workspace." >&2
    exit 1
fi

cd "$ws_path"
repo_root=$(cat .repo_root 2>/dev/null || jj root)

# Ensure [PROTECTED] exists (this may cd to repo_root)
ensure_protected "$repo_root"

# Return to workspace context
cd "$ws_path"

# Sync workspace to main (which should be [PROTECTED] now)
jj edit main 2>/dev/null || true

# Branch from behind [PROTECTED], or stack if on task
if is_protected; then
    jj new @- -m "${tag} ${task}"
else
    jj new -m "${tag} ${task}"
fi

echo "task: ${task}" >&2
echo "cwd:  ${ws_path} (persistent)" >&2
echo "${ws_path}"
