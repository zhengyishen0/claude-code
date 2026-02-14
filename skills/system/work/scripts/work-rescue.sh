#!/usr/bin/env bash
# work rescue - Move accidental changes from [PROTECTED] to proper work commit
# Usage: work rescue "task description"
set -euo pipefail

source "$(dirname "$0")/../lib/protected.sh"

task="${1:-}"
if [ -z "$task" ]; then
    echo "Usage: work rescue \"task description\"" >&2
    exit 1
fi

# Must be on [PROTECTED]
if ! is_protected; then
    echo "Not on [PROTECTED]. Nothing to rescue." >&2
    exit 1
fi

# Check for changes to rescue
changes=$(jj diff --stat 2>/dev/null || echo "")
if [ -z "$changes" ]; then
    echo "No changes to rescue — [PROTECTED] is clean." >&2
    exit 1
fi

# Get tag from workspace or session
ws_name=$(basename "${ZENIX_WORKSPACE_PATH:-$PWD}")
if [[ "$ws_name" =~ ^[a-z]+-[a-f0-9]+$ ]]; then
    tag="[${ws_name}]"
else
    # Fallback: extract session from CLAUDE_SESSION_ID if available
    session="${CLAUDE_SESSION_ID:-rescue}"
    tag="[${session:0:8}]"
fi

echo "Rescuing changes from [PROTECTED]..." >&2
echo "$changes" >&2

# Insert new commit before [PROTECTED], auto-rebases PROTECTED on top
jj new --insert-before @ -m "${tag} ${task}"

# Move changes from [PROTECTED] (now @+) into new commit (now @)
jj squash --from @+

# Recreate [PROTECTED] as child of rescue commit (not main)
jj new -m "[PROTECTED] do not edit — use \`work on\`"

echo "" >&2
echo "Rescued to: ${tag} ${task}" >&2
