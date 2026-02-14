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

# Check if workspace is detached (@ points to abandoned commit)
if ! jj log -r @ --no-graph -T 'change_id' &>/dev/null; then
    echo "Workspace detached. Re-attaching to main..." >&2
    jj workspace update-stale 2>/dev/null || true
    jj new main -m "${tag} ${task}"
    echo "task: ${task}" >&2
    echo "cwd:  ${ws_path} (persistent)" >&2
    echo "${ws_path}"
    exit 0
fi

# Ensure [PROTECTED] exists (this may cd to repo_root)
ensure_protected "$repo_root"

# Return to workspace context
cd "$ws_path"

# Determine action based on current state
msg=$(jj log -r @ --no-graph -T 'description' 2>/dev/null || echo "")
if [[ "$msg" == "${tag}"* ]]; then
    # On own task commit: stack
    jj new -m "${tag} ${task}"
else
    # On anything else (PROTECTED, merge, empty orphan): branch from main
    jj new main -m "${tag} ${task}"
fi

echo "task: ${task}" >&2
echo "cwd:  ${ws_path} (persistent)" >&2
echo "${ws_path}"
