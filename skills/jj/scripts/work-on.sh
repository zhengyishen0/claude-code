#!/usr/bin/env bash
# work-on - Start a headless agent with its own jj workspace
# Usage: work on "task description"
set -euo pipefail

task="$1"
if [ -z "$task" ]; then
    echo "Usage: work on \"task description\""
    exit 1
fi

sid=$(openssl rand -hex 4)
name="$(echo "$task" | tr ' ' '-' | tr '[:upper:]' '[:lower:]' | cut -c1-20)-${sid}"
path="$HOME/.workspaces/claude-code/${name}"

mkdir -p "$HOME/.workspaces/claude-code"

if ! jj workspace add --name "${name}" "${path}" 2>/dev/null; then
    echo "Failed to create workspace"
    exit 1
fi

echo "Workspace: ${name}"
echo "Path: ${path}"
echo "Session: ${sid}"
echo ""
echo "Starting headless agent..."

(
    cd "${path}" && \
    jj new main -m "${task} (${sid})" && \
    cc -p "${task}

Session ID: ${sid}
Workspace: ${name}

Record progress: jj new -m \"what you did and why (${sid})\"
When done, prefix final commit with: DONE:" \
    --allowedTools "Read,Write,Edit,Bash,Glob,Grep"
) &

echo ""
echo "Agent started in background."
echo ""
echo "Monitor:"
echo "  jj log                      # See progress"
echo "  jj workspace list           # See workspaces"
echo "  memory search '${sid}'      # Recall reasoning"
echo ""
echo "When ready:"
echo "  work done '${name}' 'summary'"
