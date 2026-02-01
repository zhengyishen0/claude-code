#!/usr/bin/env bash
# env.sh - Source this in ~/.zshrc:
#   source ~/Codes/claude-code/env.sh

# ============================================================
# Core paths (only these two - scripts derive the rest)
# ============================================================
export PROJECT_DIR="$HOME/Codes/claude-code"
export CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"

# ============================================================
# Tool aliases
# ============================================================
alias task="$PROJECT_DIR/task/run.sh"
alias world="$PROJECT_DIR/world/run.sh"
alias supervisor="$PROJECT_DIR/supervisor/run.sh"
# alias worktree="$PROJECT_DIR/utils/worktree.sh"  # Disabled: using jj instead
alias daemon="$PROJECT_DIR/daemon/run.sh"
alias setup="$PROJECT_DIR/setup"
alias browser="node $PROJECT_DIR/browser/cli.js"
alias memory="$PROJECT_DIR/memory/run.sh"
alias screenshot="python3 $PROJECT_DIR/utils/screenshot.py"
alias service="$PROJECT_DIR/integrations/run.sh"
alias proxy="$PROJECT_DIR/utils/proxy.sh"
alias wechat="$PROJECT_DIR/wechat/bin/wechat"

# ============================================================
# Claude CLI aliases
# ============================================================
alias claude-ps='pgrep -fl "^claude"'
alias claude-kill='pkill -9 "^claude"'
alias cc="$PROJECT_DIR/utils/cc.sh"

# ============================================================
# Daemon shortcuts (for convenience)
# ============================================================
# Quick access: world-daemon status, world-daemon log, etc.
world-daemon() {
    "$PROJECT_DIR/daemon/run.sh" world-watch "${1:-status}"
}

# ============================================================
# Auto-init: Enable proxy if reachable
# ============================================================
eval "$("$PROJECT_DIR/utils/proxy.sh" init 2>/dev/null)"
