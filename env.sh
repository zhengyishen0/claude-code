#!/usr/bin/env bash
# source ~/.zenix/env.sh

export ZENIX_ROOT="$HOME/.zenix"

# Skill aliases (skills/*/*/run → command name)
for _skill in "$ZENIX_ROOT"/skills/*/*/run; do
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
            ~/.zenix/skills/session/run list 5
            return 1
        fi
        local session_id
        session_id=$(~/.zenix/skills/session/run find "$partial") || return 1
        echo "Resuming: $session_id" >&2
        shift 2
        command claude --resume "$session_id" "$@" --model claude-opus-4-5 --allow-dangerously-skip-permissions
    else
        command claude "$@" --model claude-opus-4-5 --allow-dangerously-skip-permissions
    fi
}

alias claude-ps='pgrep -fl "^claude"'
alias claude-kill='pkill -9 "^claude"'
eval "$(~/.zenix/skills/proxy/run init 2>/dev/null)"
