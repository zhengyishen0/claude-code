#!/usr/bin/env bash
# world/commands/daemon-install.sh
# Install/uninstall the world watch LaunchAgent

set -euo pipefail

: "${PROJECT_DIR:?PROJECT_DIR not set - source env.sh}"

PLIST_TEMPLATE="$PROJECT_DIR/world/com.claude.world.watch.plist"
PLIST_DEST="$HOME/Library/LaunchAgents/com.claude.world.watch.plist"
LABEL="com.claude.world.watch"

show_help() {
    cat <<'EOF'
daemon-install - Install/manage the world watch LaunchAgent

USAGE:
    world daemon install    Install and start the daemon
    world daemon uninstall  Stop and remove the daemon
    world daemon status     Check if daemon is running
    world daemon start      Start the daemon
    world daemon stop       Stop the daemon
    world daemon restart    Restart the daemon
    world daemon log        Tail the daemon log

DESCRIPTION:
    Manages the LaunchAgent that runs the world watch daemon.
    The daemon uses fswatch to monitor task files and automatically:
    - Syncs task status to world.log
    - Spawns pending tasks
    - Recovers crashed agents
    - Archives completed tasks
EOF
}

cmd_install() {
    echo "Installing world watch daemon..."

    # Auto-install dependencies
    if ! command -v fswatch >/dev/null 2>&1; then
        echo "Installing fswatch..."
        brew install fswatch
    fi

    if ! command -v yq >/dev/null 2>&1; then
        echo "Installing yq..."
        brew install yq
    fi

    # Create directories
    mkdir -p "$HOME/Library/LaunchAgents" /tmp/world/pids

    # Generate plist from template
    sed "s|__PROJECT_DIR__|$PROJECT_DIR|g" \
        "$PLIST_TEMPLATE" > "$PLIST_DEST"

    echo "Installed: $PLIST_DEST"

    # Load the agent
    launchctl load "$PLIST_DEST" 2>/dev/null || true
    echo "Daemon started"
    echo ""
    echo "Manage with: world daemon {start|stop|status|log}"
}

cmd_uninstall() {
    echo "Uninstalling world watch daemon..."

    # Unload if running
    launchctl unload "$PLIST_DEST" 2>/dev/null || true

    # Remove plist
    rm -f "$PLIST_DEST"
    echo "Removed: $PLIST_DEST"
}

cmd_status() {
    if launchctl list 2>/dev/null | grep -q "$LABEL"; then
        echo "World daemon: running"
        launchctl list "$LABEL" 2>/dev/null | grep -E "PID|status" || true
    else
        echo "World daemon: stopped"
    fi
}

cmd_start() {
    if [ ! -f "$PLIST_DEST" ]; then
        echo "Error: Daemon not installed. Run: world daemon install" >&2
        exit 1
    fi
    launchctl load "$PLIST_DEST" 2>/dev/null && echo "Daemon started"
}

cmd_stop() {
    launchctl unload "$PLIST_DEST" 2>/dev/null && echo "Daemon stopped"
}

cmd_restart() {
    cmd_stop
    sleep 1
    cmd_start
}

cmd_log() {
    tail -f /tmp/world/daemon.log
}

case "${1:-help}" in
    install)   cmd_install ;;
    uninstall) cmd_uninstall ;;
    status)    cmd_status ;;
    start)     cmd_start ;;
    stop)      cmd_stop ;;
    restart)   cmd_restart ;;
    log)       cmd_log ;;
    help|-h|--help) show_help ;;
    *) echo "Unknown: $1"; show_help; exit 1 ;;
esac
