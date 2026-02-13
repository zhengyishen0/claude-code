#!/usr/bin/env bash
# PostToolUse hook: Snapshot workspace after edits
# Ensures jj log reflects workspace changes immediately
set -eo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# No file path means nothing to snapshot
if [[ -z "$FILE_PATH" ]]; then
    exit 0
fi

# Resolve to absolute path
if [[ "$FILE_PATH" != /* ]]; then
    FILE_PATH="$(pwd)/$FILE_PATH"
fi

# Only snapshot workspace directories
if [[ "$FILE_PATH" != "$HOME/.workspace/"* ]]; then
    exit 0
fi

# Extract workspace path (e.g., ~/.workspace/[session-id])
WORKSPACE_PATH=$(echo "$FILE_PATH" | sed -E 's|^(/[^/]+/[^/]+/[^/]+/\[[^]]+\]).*|\1|')

# Snapshot the workspace (runs jj st which triggers working copy snapshot)
if [[ -d "$WORKSPACE_PATH/.jj" ]]; then
    cd "$WORKSPACE_PATH"
    jj st >/dev/null 2>&1 || true
fi

exit 0
