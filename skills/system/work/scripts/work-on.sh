#!/usr/bin/env bash
# work on - Attach to workspace and create a new node for task
# Usage: cd "$(work on 'task')"
# Can call multiple times per session - each task gets its own node
set -euo pipefail

task="${1:-}"
if [ -z "$task" ]; then
    echo "Usage: work on \"task description\"" >&2
    exit 1
fi

# Workspace path from env (set by spawn) or current directory
ws_path="${ZENIX_WORKSPACE_PATH:-$PWD}"
ws_name=$(basename "$ws_path")    # cc-a1b2c3d4
tag="[${ws_name}]"                # [cc-a1b2c3d4]

# Validate workspace name pattern
if [[ ! "$ws_name" =~ ^[a-z]+-[a-f0-9]+$ ]]; then
    echo "Not in a workspace. Set ZENIX_WORKSPACE_PATH or cd to workspace." >&2
    exit 1
fi

cd "$ws_path"

# Branch from behind [PROTECTED], or stack if on task
msg=$(jj log -r @ --no-graph -T 'description')
if [[ "$msg" == *"[PROTECTED]"* ]]; then
    # On [PROTECTED]: branch from its parent
    jj new @^ -m "${tag} ${task}"
else
    # On task commit: stack on current
    jj new -m "${tag} ${task}"
fi

echo "task: ${task}" >&2
echo "cwd:  ${path} (persistent)" >&2

# Output path for cd
echo "${path}"
