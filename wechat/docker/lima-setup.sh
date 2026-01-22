#!/bin/bash
# Setup Redroid on macOS via Lima VM
# Architecture: Mac → Lima (Ubuntu VM) → Docker → Redroid
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VM_NAME="redroid"
REDROID_IMAGE="redroid/redroid:14.0.0_64only-latest"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[lima]${NC} $1"; }
warn() { echo -e "${YELLOW}[lima]${NC} $1"; }
error() { echo -e "${RED}[lima]${NC} $1" >&2; }

# Check if Lima is installed
check_lima() {
  if ! command -v limactl &>/dev/null; then
    error "Lima not installed. Run: brew install lima"
    exit 1
  fi
}

# Create Lima VM with Ubuntu
create_vm() {
  if limactl list 2>/dev/null | grep -q "^$VM_NAME "; then
    log "VM '$VM_NAME' already exists"
    return 0
  fi

  log "Creating Lima VM '$VM_NAME'..."

  cat > "/tmp/lima-$VM_NAME.yaml" <<'EOF'
images:
  - location: "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-arm64.img"
    arch: "aarch64"

cpus: 4
memory: "4GiB"
disk: "20GiB"

portForwards:
  - guestPort: 5555
    hostPort: 5555

containerd:
  system: false
  user: false

provision:
  - mode: system
    script: |
      #!/bin/bash
      set -eux

      export DEBIAN_FRONTEND=noninteractive

      # Install dependencies
      apt-get update
      apt-get install -y --no-install-recommends \
        linux-modules-extra-$(uname -r) \
        docker.io \
        adb

      # Enable docker
      systemctl enable docker
      systemctl start docker

      # Add user to docker group
      usermod -aG docker $(getent passwd 1000 | cut -d: -f1) || true
EOF

  limactl create --name="$VM_NAME" "/tmp/lima-$VM_NAME.yaml"
  rm -f "/tmp/lima-$VM_NAME.yaml"
}

# Start VM
start_vm() {
  local status=$(limactl list --format '{{.Status}}' "$VM_NAME" 2>/dev/null || echo "")

  if [ "$status" = "Running" ]; then
    log "VM already running"
    return 0
  fi

  log "Starting VM..."
  limactl start "$VM_NAME"
}

# Configure Docker proxy (Lima uses host proxy)
configure_docker_proxy() {
  # Get Lima's proxy IP
  local proxy_ip=$(limactl shell "$VM_NAME" -- bash -c 'echo $HTTP_PROXY' 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+' || echo "")

  if [ -z "$proxy_ip" ]; then
    return 0  # No proxy needed
  fi

  log "Configuring Docker proxy..."
  limactl shell "$VM_NAME" -- bash -c "
    if [ ! -f /etc/systemd/system/docker.service.d/http-proxy.conf ]; then
      sudo mkdir -p /etc/systemd/system/docker.service.d
      echo '[Service]
Environment=\"HTTP_PROXY=http://$proxy_ip\"
Environment=\"HTTPS_PROXY=http://$proxy_ip\"
Environment=\"NO_PROXY=localhost,127.0.0.1\"' | sudo tee /etc/systemd/system/docker.service.d/http-proxy.conf > /dev/null
      sudo systemctl daemon-reload
      sudo systemctl restart docker
    fi
  "
}

# Setup binder (load module + mount binderfs)
setup_binder() {
  log "Setting up binder..."

  limactl shell "$VM_NAME" -- bash -c '
    # Load binder module
    if ! lsmod | grep -q binder_linux; then
      sudo modprobe binder_linux devices="binder,hwbinder,vndbinder"
    fi

    # Mount binderfs if not mounted
    if ! mountpoint -q /dev/binderfs 2>/dev/null; then
      sudo mkdir -p /dev/binderfs
      sudo mount -t binder binder /dev/binderfs

      # Create binder devices
      cd /dev/binderfs
      echo binder | sudo tee binder-control > /dev/null 2>&1 || true
      echo hwbinder | sudo tee binder-control > /dev/null 2>&1 || true
      echo vndbinder | sudo tee binder-control > /dev/null 2>&1 || true

      # Create symlinks
      sudo ln -sf /dev/binderfs/binder /dev/binder 2>/dev/null || true
      sudo ln -sf /dev/binderfs/hwbinder /dev/hwbinder 2>/dev/null || true
      sudo ln -sf /dev/binderfs/vndbinder /dev/vndbinder 2>/dev/null || true
    fi
  '
}

# Start Redroid container
start_redroid() {
  local running=$(limactl shell "$VM_NAME" -- sudo docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^redroid$" && echo "1" || echo "0")

  if [ "$running" = "1" ]; then
    log "Redroid already running"
    return 0
  fi

  local exists=$(limactl shell "$VM_NAME" -- sudo docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^redroid$" && echo "1" || echo "0")

  if [ "$exists" = "1" ]; then
    log "Starting existing Redroid container..."
    limactl shell "$VM_NAME" -- sudo docker start redroid
  else
    log "Creating Redroid container..."
    limactl shell "$VM_NAME" -- sudo docker run -d \
      --name redroid \
      --privileged \
      -v /dev/binderfs:/dev/binderfs \
      -p 5555:5555 \
      "$REDROID_IMAGE" \
      androidboot.redroid_gpu_mode=guest
  fi
}

# Wait for Android to boot
wait_for_boot() {
  log "Waiting for Android to boot..."
  local max_wait=30
  local waited=0

  while [ $waited -lt $max_wait ]; do
    if adb -s localhost:5555 shell getprop sys.boot_completed 2>/dev/null | grep -q "1"; then
      log "Android booted"
      return 0
    fi
    sleep 1
    waited=$((waited + 1))
  done

  warn "Boot timeout, but container may still be starting"
}

# Connect adb from Mac
connect_adb() {
  if ! command -v adb &>/dev/null; then
    warn "adb not found. Install: brew install android-platform-tools"
    return 1
  fi

  log "Connecting adb..."
  adb connect localhost:5555 >/dev/null 2>&1
  adb -s localhost:5555 wait-for-device
  log "ADB connected"
}

# Install WeChat APK
install_wechat() {
  local apk="$SCRIPT_DIR/wechat.apk"

  if [ ! -f "$apk" ]; then
    error "WeChat APK not found at: $apk"
    error "Download from: https://www.wandoujia.com/apps/596157"
    exit 1
  fi

  log "Installing WeChat..."
  adb -s localhost:5555 install -r "$apk"
  log "WeChat installed"
}

# Open WeChat
open_wechat() {
  log "Starting WeChat..."
  adb -s localhost:5555 shell am start -n com.tencent.mm/.ui.LauncherUI
  echo ""
  log "To view screen: scrcpy -s localhost:5555"
}

# Stop Redroid
stop_redroid() {
  log "Stopping Redroid..."
  limactl shell "$VM_NAME" -- sudo docker stop redroid 2>/dev/null || true
}

# Stop VM
stop_vm() {
  log "Stopping VM..."
  limactl stop "$VM_NAME" 2>/dev/null || true
}

# Delete VM
delete_vm() {
  log "Deleting VM..."
  limactl delete -f "$VM_NAME" 2>/dev/null || true
}

# Status
status() {
  echo "=== Lima VM ==="
  limactl list 2>/dev/null | grep -E "(NAME|$VM_NAME)" || echo "Not created"

  echo ""
  echo "=== Binder ==="
  limactl shell "$VM_NAME" -- lsmod 2>/dev/null | grep binder || echo "Not loaded"

  echo ""
  echo "=== Redroid ==="
  limactl shell "$VM_NAME" -- sudo docker ps --filter name=redroid 2>/dev/null || echo "Not running"

  echo ""
  echo "=== ADB ==="
  adb devices 2>/dev/null | grep localhost || echo "Not connected"
}

# Usage
usage() {
  cat <<EOF
Lima + Redroid for macOS

Usage: $(basename "$0") <command>

Commands:
  setup     First-time setup (create VM, pull image)
  start     Start VM + Redroid + connect ADB
  stop      Stop Redroid + VM
  status    Show status
  shell     SSH into VM
  install   Install WeChat APK
  login     Open WeChat
  delete    Delete VM completely

First time:  $(basename "$0") setup && $(basename "$0") install
Daily use:   $(basename "$0") start
EOF
}

# Main
main() {
  case "${1:-}" in
    setup)
      check_lima
      create_vm
      start_vm
      configure_docker_proxy
      setup_binder
      start_redroid
      wait_for_boot
      connect_adb
      log "Setup complete!"
      ;;
    start)
      check_lima
      start_vm
      setup_binder
      start_redroid
      wait_for_boot
      connect_adb
      log "Ready!"
      ;;
    stop)
      stop_redroid
      stop_vm
      log "Stopped"
      ;;
    status)
      status
      ;;
    shell)
      limactl shell "$VM_NAME"
      ;;
    install)
      install_wechat
      ;;
    login)
      open_wechat
      ;;
    delete)
      stop_redroid
      stop_vm
      delete_vm
      log "Deleted"
      ;;
    *)
      usage
      ;;
  esac
}

main "$@"
