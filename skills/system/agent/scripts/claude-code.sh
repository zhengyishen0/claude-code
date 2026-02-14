#!/bin/bash
#
# Claude Code framework parser
# Translates ZENIX_* env vars to claude CLI flags
#
# Expected env vars (from dispatch.sh):
#   ZENIX_SESSION_ID        - Session identifier
#   ZENIX_WORKSPACE_PATH    - Full workspace path
#   ZENIX_WORKSPACE_ENABLED - true | false
#   ZENIX_MODEL_ID          - Actual model ID
#   ZENIX_PERMISSIONS       - auto | prompt
#   ZENIX_SYSTEM_PROMPT     - System prompt text
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SESSION_SCRIPT="$SCRIPT_DIR/claude-session.sh"

# ─────────────────────────────────────────────────────────────
# Session management
# ─────────────────────────────────────────────────────────────

show_recent_sessions() {
    if [[ ! -x "$SESSION_SCRIPT" ]]; then
        echo "Session script not found" >&2
        return 1
    fi

    echo "Recent sessions:" >&2
    echo "" >&2
    "$SESSION_SCRIPT" list 10
    echo "" >&2
    echo "Usage: agent -r <partial-id>" >&2
}

# ─────────────────────────────────────────────────────────────
# Build claude command
# ─────────────────────────────────────────────────────────────

CLAUDE_ARGS=()
RESUME_ID=""
CONTINUE=false
SHOW_SESSIONS=false
PROMPT=""

# Parse passthrough arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -r|--resume)
            if [[ -n "${2:-}" && "${2:0:1}" != "-" ]]; then
                RESUME_ID="$2"
                shift 2
            else
                SHOW_SESSIONS=true
                shift
            fi
            ;;
        -c|--continue)
            CONTINUE=true
            shift
            ;;
        -p)
            CLAUDE_ARGS+=("-p" "$2")
            shift 2
            ;;
        --*)
            CLAUDE_ARGS+=("$1")
            if [[ -n "${2:-}" && "${2:0:1}" != "-" ]]; then
                CLAUDE_ARGS+=("$2")
                shift
            fi
            shift
            ;;
        *)
            PROMPT="$1"
            shift
            ;;
    esac
done

# Show sessions if requested (interactive with fzf)
if [[ "$SHOW_SESSIONS" == true ]]; then
    # Get sessions, strip ANSI for fzf
    SESSIONS=$("$SESSION_SCRIPT" list 20 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g')

    if [[ -z "$SESSIONS" || "$SESSIONS" == *"no sessions"* ]]; then
        echo "No recent sessions" >&2
        exit 0
    fi

    if command -v fzf &>/dev/null; then
        SELECTED=$(echo "$SESSIONS" | fzf \
            --prompt="Resume session: " \
            --height=~15 \
            --reverse \
            --no-info) || exit 0

        [[ -z "$SELECTED" ]] && exit 0

        # Extract short ID (first field) and find full ID
        SHORT_ID=$(echo "$SELECTED" | awk '{print $1}')
        RESUME_ID=$("$SESSION_SCRIPT" find "$SHORT_ID" 2>/dev/null) || {
            echo "Session not found: $SHORT_ID" >&2
            exit 1
        }
        # Fall through to resume logic below
    else
        show_recent_sessions
        exit 0
    fi
fi

# Model
if [[ -n "${ZENIX_MODEL_ID:-}" ]]; then
    CLAUDE_ARGS+=("--model" "$ZENIX_MODEL_ID")
fi

# Permissions
case "${ZENIX_PERMISSIONS:-auto}" in
    auto)
        CLAUDE_ARGS+=("--dangerously-skip-permissions")
        ;;
    prompt)
        CLAUDE_ARGS+=("--allow-dangerously-skip-permissions")
        ;;
esac

# Workspace access
if [[ "${ZENIX_WORKSPACE_ENABLED:-false}" == "true" ]]; then
    CLAUDE_ARGS+=("--add-dir" "$HOME/.workspace")
fi

# System prompt
if [[ -n "${ZENIX_SYSTEM_PROMPT:-}" ]]; then
    CLAUDE_ARGS+=("--append-system-prompt" "$ZENIX_SYSTEM_PROMPT")
fi

# Handle resume/continue
if [[ -n "$RESUME_ID" ]]; then
    if [[ -x "$SESSION_SCRIPT" ]]; then
        FULL_ID=$("$SESSION_SCRIPT" find "$RESUME_ID") || {
            echo "Session not found: $RESUME_ID" >&2
            echo "" >&2
            show_recent_sessions
            exit 1
        }
        echo "Resuming: $FULL_ID" >&2
        CLAUDE_ARGS+=("--resume" "$FULL_ID")
    else
        CLAUDE_ARGS+=("--resume" "$RESUME_ID")
    fi
elif [[ "$CONTINUE" == true ]]; then
    CLAUDE_ARGS+=("--continue")
fi

# Add prompt if provided
if [[ -n "$PROMPT" ]]; then
    CLAUDE_ARGS+=("$PROMPT")
fi

# Execute
exec claude "${CLAUDE_ARGS[@]}"
