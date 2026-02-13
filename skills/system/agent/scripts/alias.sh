#!/usr/bin/env bash
# Skill aliases - source this in your shell rc
# Usage: source ~/.zenix/skills/system/agent/scripts/alias.sh

ZENIX_ROOT="${ZENIX_ROOT:-$HOME/.zenix}"

# Skill aliases (skills/*/*/run.sh → command name)
for _skill in "$ZENIX_ROOT"/skills/*/*/run.sh; do
    [[ -x "$_skill" ]] || continue
    _name=$(basename "$(dirname "$_skill")")
    alias $_name="$_skill"
done
unset _skill _name

# cc → agent (backwards compat)
alias cc='agent'
