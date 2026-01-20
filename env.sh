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
alias browser="$PROJECT_DIR/browser/run.sh"
alias browser-js="node $PROJECT_DIR/browser/cli.js"
alias memory="$PROJECT_DIR/memory/run.sh"
alias screenshot="$PROJECT_DIR/tools/screenshot/run.sh"
alias proxy="$PROJECT_DIR/tools/proxy/run.sh"
alias api="$PROJECT_DIR/tools/api/run.sh"

# ============================================================
# Claude CLI aliases
# ============================================================
alias claude-ps='pgrep -fl "^claude"'
alias claude-kill='pkill -9 "^claude"'
alias cc="COLUMNS=200 claude --dangerously-skip-permissions"

# ============================================================
# World daemon management
# ============================================================
world-daemon() {
    local plist="$HOME/Library/LaunchAgents/com.claude.world.watch.plist"
    case "${1:-status}" in
        start)
            launchctl load "$plist" 2>/dev/null && echo "World daemon started"
            ;;
        stop)
            launchctl unload "$plist" 2>/dev/null && echo "World daemon stopped"
            ;;
        restart)
            launchctl unload "$plist" 2>/dev/null
            launchctl load "$plist" 2>/dev/null && echo "World daemon restarted"
            ;;
        status)
            if launchctl list 2>/dev/null | grep -q "com.claude.world.watch"; then
                echo "World daemon: running"
            else
                echo "World daemon: stopped"
            fi
            ;;
        log)
            tail -f /tmp/world/daemon.log
            ;;
        *)
            echo "Usage: world-daemon {start|stop|restart|status|log}"
            ;;
    esac
}

# ============================================================
# Auto-init
# ============================================================
[[ -f "$PROJECT_DIR/tools/proxy/init.sh" ]] && source "$PROJECT_DIR/tools/proxy/init.sh"
