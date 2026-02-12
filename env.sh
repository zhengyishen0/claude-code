#!/usr/bin/env bash
# source ~/.claude-code/env.sh

# Skill aliases (skills/*/run → command name)
for _skill in ~/.claude-code/skills/*/run; do
    [[ -x "$_skill" ]] || continue
    _name=$(basename "$(dirname "$_skill")")
    alias $_name="$_skill"
done
unset _skill _name

# cc - Claude with permissions
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
export -f cc

alias claude-ps='pgrep -fl "^claude"'
alias claude-kill='pkill -9 "^claude"'

# work - agent workspace management
work() {
    case "$1" in
        on)   shift; ~/.claude-code/skills/jj/scripts/work-on.sh "$@" ;;
        done) shift; ~/.claude-code/skills/jj/scripts/work-done.sh "$@" ;;
        *)    echo "Usage: work <on|done> [args]"; return 1 ;;
    esac
}

eval "$(~/.claude-code/skills/proxy/run init 2>/dev/null)"
