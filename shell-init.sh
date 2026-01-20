#!/usr/bin/env bash
# shell-init.sh
# Source this in ~/.zshrc:
#   source ~/Codes/claude-code/shell-init.sh

# ============================================================
# Paths (single source of truth)
# ============================================================
export CLAUDE_CODE_HOME="${CLAUDE_CODE_HOME:-$HOME/Codes/claude-code}"
export PROJECT_DIR="$CLAUDE_CODE_HOME"
export PROJECT_NAME="$(basename "$PROJECT_DIR")"
export BASE_DIR="$(dirname "$PROJECT_DIR")"

# Worktrees
export WORKTREES_DIR="$BASE_DIR/.worktrees"
export PROJECT_WORKTREES="$WORKTREES_DIR/$PROJECT_NAME"
export PROJECT_ARCHIVE="$PROJECT_WORKTREES/.archive"

# Claude data
export CLAUDE_DATA_DIR="${CLAUDE_DATA_DIR:-$HOME/.claude}"
export CLAUDE_PROJECTS_DIR="$CLAUDE_DATA_DIR/projects"
export CLAUDE_TODOS_DIR="$CLAUDE_DATA_DIR/todos"

# World tool
export TASKS_DIR="$PROJECT_DIR/world/tasks"
export WORLD_LOG="$PROJECT_DIR/world/world.log"
export PID_DIR="/tmp/world/pids"

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
# Proxy auto-init (provides proxy_on/proxy_off)
[[ -f "$PROJECT_DIR/tools/proxy/init.sh" ]] && source "$PROJECT_DIR/tools/proxy/init.sh"

# Ensure directories exist
mkdir -p "$TASKS_DIR" "$PID_DIR" "$PROJECT_WORKTREES" "$PROJECT_ARCHIVE" 2>/dev/null
