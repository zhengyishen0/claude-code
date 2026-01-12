#!/bin/bash
# Proxy tool for Claude Code
# For enable/disable, use: proxy_on / proxy_off (shell functions from init.sh)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config"

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    else
        PROXY_HOST="${PROXY_HOST:-127.0.0.1}"
        PROXY_PORT="${PROXY_PORT:-33210}"
        ANTHROPIC_PROXY="${ANTHROPIC_PROXY:-https://claude-proxy.zhengyishen1.workers.dev}"
    fi
}

proxy_check() {
    load_config
    local proxy_url="http://${PROXY_HOST}:${PROXY_PORT}"

    if command -v nc &> /dev/null; then
        if nc -z -w 1 "$PROXY_HOST" "$PROXY_PORT" 2>/dev/null; then
            echo "✓ Proxy reachable at $proxy_url"
            return 0
        else
            echo "✗ Proxy not reachable at $proxy_url"
            return 1
        fi
    else
        echo "✗ nc not found"
        return 1
    fi
}

proxy_status() {
    load_config

    echo "Config: http://${PROXY_HOST}:${PROXY_PORT}"
    echo ""
    echo "Environment:"
    echo "  http_proxy=${http_proxy:-(not set)}"
    echo "  https_proxy=${https_proxy:-(not set)}"
    echo "  ANTHROPIC_BASE_URL=${ANTHROPIC_BASE_URL:-(not set)}"
    echo ""
    proxy_check
}

proxy_config() {
    case "$1" in
        edit)
            ${EDITOR:-nano} "$CONFIG_FILE"
            ;;
        show|"")
            if [ -f "$CONFIG_FILE" ]; then
                cat "$CONFIG_FILE"
            else
                echo "No config file. Run: proxy config create"
            fi
            ;;
        create)
            if [ -f "$CONFIG_FILE" ]; then
                echo "Config exists: $CONFIG_FILE"
            else
                cat > "$CONFIG_FILE" <<'EOF'
# Proxy configuration
PROXY_HOST="127.0.0.1"
PROXY_PORT="33210"
ANTHROPIC_PROXY="https://claude-proxy.zhengyishen1.workers.dev"
EOF
                echo "Created: $CONFIG_FILE"
            fi
            ;;
        *)
            echo "Usage: proxy config [show|edit|create]"
            ;;
    esac
}

show_help() {
    cat <<'EOF'
Proxy Tool
==========

Auto-enables proxy when VPN is connected.

COMMANDS:
  check         Check if proxy is reachable
  status        Show proxy status
  config        Manage config (show|edit|create)
  (no args)     Show this help

MANUAL TOGGLE (shell functions from init.sh):
  proxy_on      Enable proxy
  proxy_off     Disable proxy

SETUP:
  Add to ~/.zshrc:
    source "/path/to/tools/proxy/init.sh"
EOF
}

case "$1" in
    check)  proxy_check ;;
    status) proxy_status ;;
    config) shift; proxy_config "$@" ;;
    *)      show_help ;;
esac
