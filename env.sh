#!/usr/bin/env bash
# source ~/.zenix/env.sh

export ZENIX_ROOT="$HOME/.zenix"

# Load skill aliases from agent skill
source "$ZENIX_ROOT/skills/system/agent/scripts/alias.sh"

# Additional aliases
alias claude-ps='pgrep -fl "^claude"'
alias claude-kill='pkill -9 "^claude"'

# Proxy init
eval "$("$ZENIX_ROOT/skills/utility/proxy/run.sh" init 2>/dev/null)"
