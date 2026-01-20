#!/usr/bin/env bash
# shell-init.sh
# Source this in ~/.zshrc:
#   source ~/Codes/claude-code/shell-init.sh

# Source paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$SCRIPT_DIR/paths.sh"

# Export for child processes
export BASE_DIR PROJECT_DIR PROJECT_NAME
export PROJECT_WORKTREES PROJECT_ARCHIVE
export CLAUDE_DATA_DIR CLAUDE_PROJECTS_DIR

# Tool aliases
alias world="$PROJECT_DIR/world/run.sh"
alias supervisor="$PROJECT_DIR/supervisor/run.sh"
alias worktree="$PROJECT_DIR/worktree/run.sh"
alias browser="$PROJECT_DIR/browser/run.sh"
alias browser-js="node $PROJECT_DIR/browser/cli.js"
alias memory="$PROJECT_DIR/memory/run.sh"
alias screenshot="$PROJECT_DIR/tools/screenshot/run.sh"
alias proxy="$PROJECT_DIR/tools/proxy/run.sh"

# Proxy auto-init
[[ -f "$PROJECT_DIR/tools/proxy/init.sh" ]] && source "$PROJECT_DIR/tools/proxy/init.sh"
