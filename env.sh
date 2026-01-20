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
alias world="$PROJECT_DIR/world/run.sh"
alias supervisor="$PROJECT_DIR/supervisor/run.sh"
alias worktree="$PROJECT_DIR/worktree/run.sh"
alias daemon="$PROJECT_DIR/daemon/run.sh"
alias browser="$PROJECT_DIR/browser/run.sh"
alias browser-js="node $PROJECT_DIR/browser/cli.js"
alias memory="$PROJECT_DIR/memory/run.sh"
alias screenshot="python3 $PROJECT_DIR/tools/screenshot.py"
alias proxy="$PROJECT_DIR/tools/proxy.sh"
alias service="$PROJECT_DIR/service/run.sh"

# ============================================================
# Claude CLI aliases
# ============================================================
alias claude-ps='pgrep -fl "^claude"'
alias claude-kill='pkill -9 "^claude"'
alias cc="COLUMNS=200 claude --dangerously-skip-permissions"

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
if command -v nc &>/dev/null && nc -z -w 1 127.0.0.1 33210 &>/dev/null; then
    export http_proxy="http://127.0.0.1:33210"
    export https_proxy="http://127.0.0.1:33210"
    export ANTHROPIC_BASE_URL="https://claude-proxy.zhengyishen1.workers.dev"
fi
