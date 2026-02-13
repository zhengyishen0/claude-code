#!/bin/bash
# proxy - Proxy management tool
set -euo pipefail

CONFIG_FILE="$ZENIX_ROOT/skills/utility/proxy/proxy.conf"

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    else
        PROXY_HOST="${PROXY_HOST:-127.0.0.1}"
        PROXY_PORT="${PROXY_PORT:-33210}"
        ANTHROPIC_PROXY="${ANTHROPIC_PROXY:-https://claude-proxy.zhengyishen1.workers.dev}"
    fi
}

# Check if proxy is reachable (silent, just return code)
is_reachable() {
    command -v nc &>/dev/null && nc -z -w 1 "$PROXY_HOST" "$PROXY_PORT" 2>/dev/null
}

proxy_check() {
    load_config
    local proxy_url="http://${PROXY_HOST}:${PROXY_PORT}"

    if ! command -v nc &>/dev/null; then
        echo "nc not found"
        return 1
    fi

    if is_reachable; then
        echo "Proxy reachable at $proxy_url"
        return 0
    else
        echo "Proxy not reachable at $proxy_url"
        return 1
    fi
}

# Output export commands if proxy is reachable (for eval in env.sh)
proxy_init() {
    load_config
    if is_reachable; then
        echo "export http_proxy=\"http://${PROXY_HOST}:${PROXY_PORT}\""
        echo "export https_proxy=\"http://${PROXY_HOST}:${PROXY_PORT}\""
        echo "export ANTHROPIC_BASE_URL=\"$ANTHROPIC_PROXY\""
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
    case "${1:-show}" in
        edit)
            ${EDITOR:-nano} "$CONFIG_FILE"
            ;;
        show)
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
proxy - Proxy management tool

USAGE
    proxy status        Show proxy status and environment
    proxy check         Check if proxy is reachable
    proxy config        Manage config (show|edit|create)

NOTES
    Proxy auto-enables on shell startup if reachable (via env.sh).
    To manually toggle, open a new terminal or set env vars directly.
EOF
}

case "${1:-}" in
    init)   proxy_init ;;
    check)  proxy_check ;;
    status) proxy_status ;;
    config) shift; proxy_config "$@" ;;
    -h|--help|help) show_help ;;
    *)      show_help ;;
esac
