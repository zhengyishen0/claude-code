#!/usr/bin/env bash
# daemon/run.sh - Generic LaunchAgent daemon manager
# Manages all daemons defined in daemon/plists/

set -euo pipefail

: "${PROJECT_DIR:?PROJECT_DIR not set - source env.sh}"

DAEMON_DIR="$PROJECT_DIR/daemon"
PLISTS_DIR="$DAEMON_DIR/plists"
LAUNCHAGENTS_DIR="$HOME/Library/LaunchAgents"

show_help() {
    cat <<'EOF'
daemon - LaunchAgent daemon manager

USAGE:
    daemon list                     List available daemons
    daemon <name> install           Install and start daemon
    daemon <name> uninstall         Stop and remove daemon
    daemon <name> start             Start daemon
    daemon <name> stop              Stop daemon
    daemon <name> restart           Restart daemon
    daemon <name> status            Check daemon status
    daemon <name> log               Tail daemon log

AVAILABLE DAEMONS:
EOF
    list_daemons "    "
    cat <<'EOF'

ADDING NEW DAEMONS:
    1. Create script: daemon/<name>.sh
    2. Create plist:  daemon/plists/com.claude.<name>.plist
    3. Use __PROJECT_DIR__ placeholder in plist (auto-substituted)

EXAMPLES:
    daemon world-watch install
    daemon world-watch status
    daemon world-watch log
EOF
}

list_daemons() {
    local prefix="${1:-}"
    for plist in "$PLISTS_DIR"/*.plist; do
        [ -e "$plist" ] || continue
        local name=$(basename "$plist" .plist | sed 's/^com\.claude\.//')
        local label=$(basename "$plist" .plist)
        local installed=""
        if [ -f "$LAUNCHAGENTS_DIR/$(basename "$plist")" ]; then
            if launchctl list 2>/dev/null | grep -q "$label"; then
                installed=" [running]"
            else
                installed=" [installed]"
            fi
        fi
        echo "${prefix}${name}${installed}"
    done
}

get_plist_template() {
    local name="$1"
    local plist="$PLISTS_DIR/com.claude.$name.plist"
    if [ ! -f "$plist" ]; then
        echo "Error: No plist found for daemon '$name'" >&2
        echo "Expected: $plist" >&2
        exit 1
    fi
    echo "$plist"
}

get_plist_dest() {
    local name="$1"
    echo "$LAUNCHAGENTS_DIR/com.claude.$name.plist"
}

get_label() {
    local name="$1"
    echo "com.claude.$name"
}

get_log_file() {
    local name="$1"
    # Extract from plist or use default
    echo "/tmp/${name}/daemon.log"
}

cmd_install() {
    local name="$1"
    local template=$(get_plist_template "$name")
    local dest=$(get_plist_dest "$name")
    local label=$(get_label "$name")

    echo "Installing $name daemon..."

    # Create directories
    mkdir -p "$LAUNCHAGENTS_DIR" "/tmp/${name}"

    # Generate plist from template
    sed "s|__PROJECT_DIR__|$PROJECT_DIR|g" "$template" > "$dest"
    echo "Installed: $dest"

    # Load the agent
    launchctl load "$dest" 2>/dev/null || true
    echo "Daemon started"
    echo ""
    echo "Manage with: daemon $name {start|stop|status|log}"
}

cmd_uninstall() {
    local name="$1"
    local dest=$(get_plist_dest "$name")

    echo "Uninstalling $name daemon..."
    launchctl unload "$dest" 2>/dev/null || true
    rm -f "$dest"
    echo "Removed: $dest"
}

cmd_start() {
    local name="$1"
    local dest=$(get_plist_dest "$name")

    if [ ! -f "$dest" ]; then
        echo "Error: Daemon not installed. Run: daemon $name install" >&2
        exit 1
    fi
    launchctl load "$dest" 2>/dev/null && echo "$name daemon started"
}

cmd_stop() {
    local name="$1"
    local dest=$(get_plist_dest "$name")
    launchctl unload "$dest" 2>/dev/null && echo "$name daemon stopped"
}

cmd_restart() {
    local name="$1"
    cmd_stop "$name" || true
    sleep 1
    cmd_start "$name"
}

cmd_status() {
    local name="$1"
    local label=$(get_label "$name")

    if launchctl list 2>/dev/null | grep -q "$label"; then
        echo "$name daemon: running"
        launchctl list "$label" 2>/dev/null || true
    else
        echo "$name daemon: stopped"
    fi
}

cmd_log() {
    local name="$1"
    local log_file=$(get_log_file "$name")

    if [ -f "$log_file" ]; then
        tail -f "$log_file"
    else
        echo "No log file found at: $log_file"
        echo "Checking stderr log..."
        tail -f "/tmp/${name}/daemon.stderr.log" 2>/dev/null || echo "No logs found"
    fi
}

# Parse arguments
case "${1:-help}" in
    list)
        echo "Available daemons:"
        list_daemons "  "
        ;;
    help|-h|--help)
        show_help
        ;;
    *)
        # First arg is daemon name, second is command
        DAEMON_NAME="$1"
        COMMAND="${2:-status}"

        case "$COMMAND" in
            install)   cmd_install "$DAEMON_NAME" ;;
            uninstall) cmd_uninstall "$DAEMON_NAME" ;;
            start)     cmd_start "$DAEMON_NAME" ;;
            stop)      cmd_stop "$DAEMON_NAME" ;;
            restart)   cmd_restart "$DAEMON_NAME" ;;
            status)    cmd_status "$DAEMON_NAME" ;;
            log)       cmd_log "$DAEMON_NAME" ;;
            *)         echo "Unknown command: $COMMAND"; show_help; exit 1 ;;
        esac
        ;;
esac
