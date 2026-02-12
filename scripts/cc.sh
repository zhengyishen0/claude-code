#!/usr/bin/env bash
# cc - Claude Code wrapper
#
# Usage:
#   cc                    Start new session
#   cc -r <partial>       Resume session by partial ID
#   cc <args>             Pass through to claude

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SESSION_SKILL="$SCRIPT_DIR/../skills/session/run"

if [[ "${1:-}" == "-r" || "${1:-}" == "--resume" ]]; then
    partial="${2:-}"
    if [[ -z "$partial" ]]; then
        echo "Usage: cc -r <partial-session-id>" >&2
        echo "" >&2
        "$SESSION_SKILL" list 5
        exit 1
    fi

    session_id=$("$SESSION_SKILL" find "$partial") || exit 1
    echo "Resuming: $session_id" >&2
    shift 2
    exec claude --resume "$session_id" "$@"
fi

exec claude "$@"
