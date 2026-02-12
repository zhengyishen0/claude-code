#!/usr/bin/env bash
# env.sh - Source this in ~/.zshrc:
#   source ~/.claude-code/env.sh

# ============================================================
# Auto-discover skills (creates aliases for skills/*/run)
# ============================================================
for _skill in ~/.claude-code/skills/*/run; do
    [[ -x "$_skill" ]] || continue
    _name=$(basename "$(dirname "$_skill")")
    alias $_name="$_skill"
done
unset _skill _name

# ============================================================
# cc - Claude Code wrapper
# ============================================================
# Usage:
#   cc                    Start new session
#   cc -r <partial>       Resume session by partial ID
#   cc <args>             Pass through to claude

cc() {
    if [[ "${1:-}" == "-r" || "${1:-}" == "--resume" ]]; then
        local partial="${2:-}"
        if [[ -z "$partial" ]]; then
            echo "Usage: cc -r <partial-session-id>" >&2
            echo "" >&2
            ~/.claude-code/skills/session/run list 5
            return 1
        fi

        local session_id
        session_id=$(~/.claude-code/skills/session/run find "$partial") || return 1
        echo "Resuming: $session_id" >&2
        shift 2
        command claude --resume "$session_id" "$@" --allow-dangerously-skip-permissions
    else
        command claude "$@" --allow-dangerously-skip-permissions
    fi
}

# ============================================================
# Claude CLI aliases
# ============================================================
alias claude-ps='pgrep -fl "^claude"'
alias claude-kill='pkill -9 "^claude"'

# ============================================================
# Auto-init: Enable proxy if reachable
# ============================================================
eval "$(~/.claude-code/skills/proxy/run init 2>/dev/null)"

# ============================================================
# work - Agent workspace management (delegates to jj skill)
# ============================================================
# Usage:
#   work on "task"       Start headless agent with workspace
#   work done "ws"       Merge workspace to main and cleanup

work() {
    local cmd="$1"
    shift
    case "$cmd" in
        on)   ~/.claude-code/skills/jj/scripts/work-on.sh "$@" ;;
        done) ~/.claude-code/skills/jj/scripts/work-done.sh "$@" ;;
        *)
            echo "Usage: work <on|done> [args]"
            echo "  on \"task\"       Start headless agent with workspace"
            echo "  done \"ws\"       Merge workspace to main and cleanup"
            return 1
            ;;
    esac
}
