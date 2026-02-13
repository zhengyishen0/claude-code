#!/usr/bin/env bash
# source ~/.zenix/env.sh

export ZENIX_ROOT="$HOME/.zenix"

# Add bin/ to PATH (skill commands: work, browser, next, etc.)
export PATH="$ZENIX_ROOT/bin:$PATH"

# Dangerous command aliases (bypass for blocked commands)
_BLOCKED_YAML="$ZENIX_ROOT/skills/system/work/config/blocked.yaml"
if [[ -f "$_BLOCKED_YAML" ]] && command -v yq &>/dev/null; then
    while IFS=$'\t' read -r _alias _cmd; do
        [[ -n "$_alias" && -n "$_cmd" ]] || continue
        eval "$_alias() { $_cmd \"\$@\"; }"
    done < <(yq -r '.[] | "\(.alias)\t\(.command)"' "$_BLOCKED_YAML" 2>/dev/null)
fi
unset _BLOCKED_YAML _alias _cmd

# Additional aliases
alias claude-ps='pgrep -fl "^claude"'
alias claude-kill='pkill -9 "^claude"'

# Proxy init
eval "$("$ZENIX_ROOT/skills/utility/proxy/run.sh" init 2>/dev/null)"
