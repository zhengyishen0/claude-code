#!/usr/bin/env bash
# PreToolUse hook: Block dangerous operations
# 1. Edit/Write outside workspace directories
# 2. Dangerous commands (jj abandon, git push --force, etc.)
set -eo pipefail

ZENIX_ROOT="${ZENIX_ROOT:-$HOME/.zenix}"
BLOCKED_YAML="$ZENIX_ROOT/skills/system/work/config/blocked.yaml"

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

# === BASH COMMAND BLOCKING ===
if [[ "$TOOL_NAME" == "Bash" ]]; then
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

    if [[ -f "$BLOCKED_YAML" ]] && command -v yq &>/dev/null; then
        while IFS=$'\t' read -r pattern alias; do
            [[ -n "$pattern" ]] || continue
            if echo "$COMMAND" | grep -qE "$pattern"; then
                cat >&2 << EOF

BLOCKED: Dangerous command detected.

Pattern matched: $pattern
Use the uppercase alias instead: $alias

Example:
  $alias <args>

EOF
                exit 2
            fi
        done < <(yq -r '.[] | "\(.pattern)\t\(.alias)"' "$BLOCKED_YAML" 2>/dev/null)
    fi
    exit 0
fi

# === EDIT/WRITE BLOCKING (workspace enforcement) ===
if [[ "$TOOL_NAME" != "Edit" && "$TOOL_NAME" != "Write" ]]; then
    exit 0
fi

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# No file path means something else is happening
if [[ -z "$FILE_PATH" ]]; then
    exit 0
fi

# Resolve to absolute path
if [[ "$FILE_PATH" != /* ]]; then
    FILE_PATH="$(pwd)/$FILE_PATH"
fi
FILE_PATH=$(cd "$(dirname "$FILE_PATH")" 2>/dev/null && pwd)/$(basename "$FILE_PATH") 2>/dev/null || FILE_PATH="$FILE_PATH"

# Allow: Files in workspace directories
if [[ "$FILE_PATH" == "$HOME/.workspace/"* ]]; then
    exit 0
fi

# Allow: Temporary files
if [[ "$FILE_PATH" == /tmp/* || "$FILE_PATH" == */tmp/* || "$FILE_PATH" == */.tmp/* ]]; then
    exit 0
fi

# Allow: Claude's own data directories
if [[ "$FILE_PATH" == "$HOME/.claude/"* ]]; then
    exit 0
fi

# Allow: Memory/auto-memory files (inside zenix repo but needed for learning)
if [[ "$FILE_PATH" == *"/memory/"* && "$FILE_PATH" == *"/.claude/"* ]]; then
    exit 0
fi

# Check if file is in a jj repository
FILE_DIR=$(dirname "$FILE_PATH")
if ! cd "$FILE_DIR" 2>/dev/null; then
    # Directory doesn't exist yet, check parent
    FILE_DIR=$(dirname "$FILE_DIR")
    cd "$FILE_DIR" 2>/dev/null || exit 0  # Can't determine, allow
fi

# Not a jj repo? Allow (could be any random file)
if ! jj root &>/dev/null; then
    exit 0
fi

# Check if we're in a workspace (directory name starts with [)
WORKSPACE_NAME=$(basename "$(pwd)")
if [[ "$WORKSPACE_NAME" == "["* ]]; then
    exit 0
fi

# Check jj workspace list to see if current dir is a named workspace
CURRENT_WORKSPACE=$(jj workspace list 2>/dev/null | grep -E '^\* ' | awk '{print $2}' || echo "default")
if [[ "$CURRENT_WORKSPACE" != "default" ]]; then
    exit 0
fi

# We're in the main repo on the default workspace - BLOCK
cat >&2 << 'EOF'

BLOCKED: Cannot edit files directly in main repository.

You must create a workspace first:
  work on "your task description" && cd ~/.workspace/[SESSION_ID]

This ensures:
- All changes are isolated and traceable
- Main branch stays clean
- Easy rollback if needed

EOF

exit 2
