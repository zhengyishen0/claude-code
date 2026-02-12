#!/usr/bin/env bash
# vcs on - Create a jj workspace for a task
# Usage: vcs on "task description"
set -euo pipefail

task="$1"
if [ -z "$task" ]; then
    echo "Usage: vcs on \"task description\""
    exit 1
fi

sid=$(openssl rand -hex 4)
slug="$(echo "$task" | tr ' ' '-' | tr '[:upper:]' '[:lower:]' | cut -c1-20)-${sid}"
path="$HOME/.workspaces/claude-code/${slug}"

mkdir -p "$HOME/.workspaces/claude-code"

if ! jj workspace add --name "${slug}" "${path}" 2>/dev/null; then
    echo "Failed to create workspace"
    exit 1
fi

cd "${path}"
jj new main -m "[${sid}] ${task}"

echo ""
echo "Workspace: ${slug}"
echo "Path:      ${path}"
echo "Session:   ${sid}"
echo ""
echo "cd '${path}'"
echo "vcs done '${slug}' when finished"
