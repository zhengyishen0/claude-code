#!/bin/bash
# Setup Redroid container with WeChat
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINER_NAME="wechat-android"
REDROID_IMAGE="redroid/redroid:14.0.0_64only-latest"
WECHAT_APK="$SCRIPT_DIR/wechat.apk"
DATA_DIR="$SCRIPT_DIR/../data"

# Check if running on Linux
check_platform() {
  if [[ "$(uname)" != "Linux" ]]; then
    echo "Error: Redroid requires Linux kernel modules (binder, ashmem)." >&2
    echo "" >&2
    echo "Options:" >&2
    echo "  1. Run this on a Linux machine/VM" >&2
    echo "  2. Use Android emulator instead (works on Mac)" >&2
    exit 1
  fi
}

# Check dependencies
check_deps() {
  local missing=""
  command -v docker >/dev/null || missing="$missing docker"
  command -v adb >/dev/null || missing="$missing adb"

  if [ -n "$missing" ]; then
    echo "Missing:$missing" >&2
    exit 1
  fi
}

# Start Redroid container
start_container() {
  if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "Container exists, starting..."
    docker start "$CONTAINER_NAME"
  else
    echo "Creating container..."
    docker run -d --name "$CONTAINER_NAME" \
      --privileged \
      -v "$DATA_DIR:/data/local/wechat" \
      -p 5555:5555 \
      "$REDROID_IMAGE"
  fi

  # Wait for boot
  echo "Waiting for Android to boot..."
  sleep 10
}

# Connect adb
connect_adb() {
  echo "Connecting adb..."
  adb connect localhost:5555
  adb -s localhost:5555 wait-for-device
  echo "Connected."
}

# Install WeChat
install_wechat() {
  if [ ! -f "$WECHAT_APK" ]; then
    echo "WeChat APK not found at: $WECHAT_APK" >&2
    echo "Download from: https://www.wandoujia.com/apps/596157" >&2
    exit 1
  fi

  echo "Installing WeChat..."
  adb -s localhost:5555 install -r "$WECHAT_APK"
  echo "Installed."
}

# Open WeChat for login
open_wechat() {
  echo "Starting WeChat..."
  adb -s localhost:5555 shell am start -n com.tencent.mm/.ui.LauncherUI

  echo ""
  echo "WeChat started. To view screen for QR login:"
  echo "  scrcpy -s localhost:5555"
  echo ""
  echo "After login, run: wechat sync"
}

# Main
main() {
  case "${1:-start}" in
    start)
      check_platform
      check_deps
      start_container
      connect_adb
      ;;
    install)
      install_wechat
      ;;
    login)
      open_wechat
      ;;
    stop)
      docker stop "$CONTAINER_NAME"
      ;;
    *)
      echo "Usage: setup.sh [start|install|login|stop]"
      ;;
  esac
}

main "$@"
