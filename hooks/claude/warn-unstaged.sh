#!/bin/bash
# PreToolUse hook: Warn if unstaged changes exist
# Soft reminder - does not block, just warns
#
# Exit code 0 = allow (with optional warning to stderr)

set -eo pipefail

input=$(cat)

# Get target file path and its directory
file_path=$(echo "$input" | jq -r '.tool_input.file_path // ""')
target_dir=$(dirname "$file_path")

# Determine git directory for checks
if [[ -d "$target_dir" ]]; then
    git_dir="$target_dir"
else
    git_dir="."
fi

# Get unstaged files (modified + untracked)
unstaged=$(git -C "$git_dir" status --porcelain 2>/dev/null | grep -E '^(\?\?| M|MM| D)' | awk '{print $2}' | head -5 || true)

if [[ -n "$unstaged" ]]; then
    count=$(git -C "$git_dir" status --porcelain 2>/dev/null | grep -cE '^(\?\?| M|MM| D)' || echo 0)
    echo "⚠️  Unstaged changes ($count files). Clean up before continuing:" >&2
    echo "$unstaged" | sed 's/^/   /' >&2
    [[ $count -gt 5 ]] && echo "   ... and $((count - 5)) more" >&2
    echo "" >&2
    echo "Consider: git add | git checkout | mv to tmp/ | rm (if not needed)" >&2
    echo "" >&2
fi

exit 0
