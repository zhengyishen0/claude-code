#!/usr/bin/env bash
# work on - Create a jj workspace for agent session
# Usage: cd "$(work on 'task')"
set -euo pipefail

: "${ZENIX_WORKSPACE:=$HOME/.workspace}"

task="${1:-}"
if [ -z "$task" ]; then
    echo "Usage: work on \"task description\"" >&2
    exit 1
fi

# Use agent session ID if available, otherwise generate one
sid="${CLAUDE_SESSION_ID:-$(openssl rand -hex 4)}"
sid="${sid:0:8}"

name="[${sid}]"
path="$ZENIX_WORKSPACE/${name}"

# Save repo root before creating workspace
repo_root=$(jj root)

mkdir -p "$ZENIX_WORKSPACE"

if ! jj workspace add --name "${name}" "${path}" 2>/dev/null; then
    echo "Failed to create workspace" >&2
    exit 1
fi

# Store repo root for work done
echo "$repo_root" > "${path}/.repo_root"

cd "${path}"
jj new main -m "[${sid}] ${task}"

echo "task: ${task}" >&2
echo "cwd:  ${path} (persistent)" >&2

# Output path for cd
echo "${path}"
