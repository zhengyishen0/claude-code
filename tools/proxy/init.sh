#!/bin/bash
# Claude Code Proxy Auto-Enable
# Source this file in ~/.zshrc to auto-enable proxy when VPN is connected

_PROXY_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_PROXY_CONFIG_FILE="$_PROXY_SCRIPT_DIR/config"

# Load proxy configuration
if [ -f "$_PROXY_CONFIG_FILE" ]; then
    source "$_PROXY_CONFIG_FILE"
else
    PROXY_HOST="${PROXY_HOST:-127.0.0.1}"
    PROXY_PORT="${PROXY_PORT:-33210}"
    ANTHROPIC_PROXY="${ANTHROPIC_PROXY:-https://claude-proxy.zhengyishen1.workers.dev}"
fi

# Manual enable
proxy_on() {
    export http_proxy="http://${PROXY_HOST}:${PROXY_PORT}"
    export https_proxy="http://${PROXY_HOST}:${PROXY_PORT}"
    export ANTHROPIC_BASE_URL="$ANTHROPIC_PROXY"
    echo "Proxy enabled: http://${PROXY_HOST}:${PROXY_PORT}"
}

# Manual disable
proxy_off() {
    unset http_proxy https_proxy ANTHROPIC_BASE_URL
    echo "Proxy disabled"
}

# Auto-enable on shell startup if proxy is reachable
if command -v nc &> /dev/null; then
    nc -z -w 1 "$PROXY_HOST" "$PROXY_PORT" &>/dev/null && proxy_on > /dev/null
fi
