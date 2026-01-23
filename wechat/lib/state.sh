#!/bin/bash
# state.sh - State checking functions for WeChat tool
# Source this file to use the functions

WECHAT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_DIR="$WECHAT_DIR/data"
AVD_NAME="WeChat_Tablet"
AVD_DIR="$HOME/.android/avd/${AVD_NAME}.avd"
SNAPSHOT_NAME="wechat_logged_in"
EMULATOR_PATH="/opt/homebrew/share/android-commandlinetools/emulator/emulator"
ADB_PATH="/opt/homebrew/share/android-commandlinetools/platform-tools/adb"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Check if emulator tools are installed
check_emulator_installed() {
    [[ -x "$EMULATOR_PATH" ]] && [[ -x "$ADB_PATH" ]]
}

# Check if AVD exists
check_avd_exists() {
    [[ -d "$AVD_DIR" ]]
}

# Check if we have a logged-in snapshot
check_snapshot_exists() {
    [[ -d "$AVD_DIR/snapshots/$SNAPSHOT_NAME" ]]
}

# Check if database exists locally
check_database_exists() {
    [[ -f "$DATA_DIR/EnMicroMsg.db" ]]
}

# Check if encryption key is configured
check_key_exists() {
    [[ -f "$DATA_DIR/config.env" ]] && grep -q "WECHAT_KEY=" "$DATA_DIR/config.env"
}

# Get last sync time (returns empty if never synced)
get_last_sync_time() {
    if [[ -f "$DATA_DIR/EnMicroMsg.db" ]]; then
        stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$DATA_DIR/EnMicroMsg.db" 2>/dev/null || \
        stat -c "%y" "$DATA_DIR/EnMicroMsg.db" 2>/dev/null | cut -d. -f1
    fi
}

# Get human-readable time since last sync
get_sync_age() {
    if [[ -f "$DATA_DIR/EnMicroMsg.db" ]]; then
        local mtime=$(stat -f "%m" "$DATA_DIR/EnMicroMsg.db" 2>/dev/null || stat -c "%Y" "$DATA_DIR/EnMicroMsg.db" 2>/dev/null)
        local now=$(date +%s)
        local diff=$((now - mtime))

        if [[ $diff -lt 60 ]]; then
            echo "just now"
        elif [[ $diff -lt 3600 ]]; then
            echo "$((diff / 60)) minutes ago"
        elif [[ $diff -lt 86400 ]]; then
            echo "$((diff / 3600)) hours ago"
        else
            echo "$((diff / 86400)) days ago"
        fi
    else
        echo "never"
    fi
}

# Check if emulator is running
check_emulator_running() {
    "$ADB_PATH" devices 2>/dev/null | grep -q "emulator-5554"
}

# Get overall state
# Returns: "needs_setup", "needs_onboard", "needs_sync", "ready"
get_state() {
    if ! check_emulator_installed || ! check_avd_exists; then
        echo "needs_setup"
    elif ! check_snapshot_exists; then
        echo "needs_onboard"
    elif ! check_database_exists || ! check_key_exists; then
        echo "needs_sync"
    else
        echo "ready"
    fi
}

# Print status summary
print_status() {
    echo -e "${BOLD}WeChat Search Status${NC}"
    echo "===================="

    if check_emulator_installed; then
        echo -e "Emulator:  ${GREEN}installed${NC}"
    else
        echo -e "Emulator:  ${RED}not installed${NC}"
    fi

    if check_avd_exists; then
        echo -e "AVD:       ${GREEN}exists${NC}"
    else
        echo -e "AVD:       ${RED}not found${NC}"
    fi

    if check_snapshot_exists; then
        echo -e "Snapshot:  ${GREEN}saved${NC}"
    else
        echo -e "Snapshot:  ${YELLOW}not saved${NC}"
    fi

    if check_database_exists; then
        echo -e "Database:  ${GREEN}synced${NC} ($(get_sync_age))"
    else
        echo -e "Database:  ${RED}not synced${NC}"
    fi

    if check_emulator_running; then
        echo -e "Emulator:  ${GREEN}running${NC}"
    else
        echo -e "Emulator:  ${YELLOW}stopped${NC}"
    fi

    echo ""
    echo "State: $(get_state)"
}

# Ensure ready state, triggering setup/onboard as needed
# Returns 0 if ready, 1 if user cancelled
ensure_ready() {
    local state=$(get_state)

    # Handle needs_setup
    if [[ "$state" == "needs_setup" ]]; then
        echo -e "${YELLOW}First time setup required.${NC}"
        echo ""
        "$WECHAT_DIR/bin/dev" setup || return 1
        state=$(get_state)
    fi

    # Handle needs_onboard
    if [[ "$state" == "needs_onboard" ]]; then
        echo -e "${YELLOW}Login required.${NC}"
        echo ""
        "$WECHAT_DIR/bin/dev" onboard || return 1
        state=$(get_state)
    fi

    # Handle needs_sync
    if [[ "$state" == "needs_sync" ]]; then
        echo -e "${YELLOW}Syncing database...${NC}"
        "$WECHAT_DIR/bin/sync" || return 1
        state=$(get_state)
    fi

    # Final check
    if [[ "$state" == "ready" ]]; then
        return 0
    else
        echo -e "${RED}Setup incomplete. Please try again.${NC}"
        return 1
    fi
}
