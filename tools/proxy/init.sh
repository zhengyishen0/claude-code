#!/bin/bash
# Claude Code Proxy Auto-Enable
# This script is sourced by shell startup files to automatically enable proxy when available

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="$REPO_ROOT/.proxy-config"

# Load proxy configuration
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    # Default configuration
    PROXY_HOST="${PROXY_HOST:-127.0.0.1}"
    PROXY_PORT="${PROXY_PORT:-33210}"
    ANTHROPIC_PROXY="${ANTHROPIC_PROXY:-https://claude-proxy.zhengyishen1.workers.dev}"
fi

# Quick check if proxy is reachable (silent, fast)
_claude_proxy_check() {
    # Try nc first (fastest, ~10ms)
    if command -v nc &> /dev/null; then
        nc -z -w 1 "$PROXY_HOST" "$PROXY_PORT" &>/dev/null
        return $?
    fi

    # Fallback to timeout + curl
    if command -v timeout &> /dev/null && command -v curl &> /dev/null; then
        timeout 1 curl -s -x "http://${PROXY_HOST}:${PROXY_PORT}" -o /dev/null http://example.com &>/dev/null
        return $?
    fi

    # No way to check, assume not available
    return 1
}

# Auto-enable proxy if reachable
if _claude_proxy_check; then
    export http_proxy="http://${PROXY_HOST}:${PROXY_PORT}"
    export https_proxy="http://${PROXY_HOST}:${PROXY_PORT}"
    export ANTHROPIC_BASE_URL="$ANTHROPIC_PROXY"
fi

# Clean up helper function
unset -f _claude_proxy_check
