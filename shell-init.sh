#!/usr/bin/env bash
# shell-init.sh
# Source this file in your .zshrc or .bashrc to enable claude-tools aliases
#
# Usage: Add to ~/.zshrc:
#   source /path/to/claude-code/shell-init.sh

# Get the directory where this script is located
CLAUDE_CODE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

# Export for use by tools
export CLAUDE_CODE_DIR

# Tool aliases
alias world="$CLAUDE_CODE_DIR/world/run.sh"
alias supervisor="$CLAUDE_CODE_DIR/supervisor/run.sh"
alias browser="$CLAUDE_CODE_DIR/browser/run.sh"
alias memory="$CLAUDE_CODE_DIR/memory/run.sh"

# Optional: shorter aliases
alias sv="supervisor"
alias wld="world"
