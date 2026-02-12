#!/usr/bin/env bash
# vcs on - Create a jj workspace
# Usage: cd "$(vcs on 'task description')"
set -euo pipefail

task="$1"
if [ -z "$task" ]; then
    echo "Usage: vcs on \"task description\"" >&2
    exit 1
fi

# Use agent session ID if available, otherwise generate one
sid="${CLAUDE_SESSION_ID:-$(openssl rand -hex 4)}"
sid="${sid:0:8}"

name="[${sid}]"
path="$(dirname ~/.claude-code)/${name}"

if ! jj workspace add --name "${name}" "${path}" 2>/dev/null; then
    echo "Failed to create workspace" >&2
    exit 1
fi

cd "${path}"
jj new main -m "[${sid}] ${task}" >&2

echo "Workspace: ${name}" >&2
echo "Session:   ${sid}" >&2

# stdout: path only (for cd)
echo "${path}"
