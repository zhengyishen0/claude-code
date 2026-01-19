#!/usr/bin/env bash
# shell-init.sh
# Source this in ~/.zshrc:
#   source /path/to/claude-code/shell-init.sh

CLAUDE_CODE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
export CLAUDE_CODE_DIR

# Tool aliases
alias world="$CLAUDE_CODE_DIR/world/run.sh"
alias supervisor="$CLAUDE_CODE_DIR/supervisor/run.sh"
alias browser="$CLAUDE_CODE_DIR/browser/run.sh"
alias memory="$CLAUDE_CODE_DIR/memory/run.sh"

# Short aliases
alias sv="supervisor"
alias wld="world"
