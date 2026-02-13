#!/usr/bin/env bash
# source ~/.zenix/env.sh

export ZENIX_ROOT="$HOME/.zenix"

# Main CLI
alias next='$ZENIX_ROOT/skills/system/next/run.sh'

# Additional aliases
alias claude-ps='pgrep -fl "^claude"'
alias claude-kill='pkill -9 "^claude"'

# Proxy init
eval "$("$ZENIX_ROOT/skills/utility/proxy/run.sh" init 2>/dev/null)"
