#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR/../..")"
CONFIG_FILE="$REPO_ROOT/.proxy-config"

# Load proxy configuration
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    else
        # Default configuration
        PROXY_HOST="${PROXY_HOST:-127.0.0.1}"
        PROXY_PORT="${PROXY_PORT:-33210}"
        ANTHROPIC_PROXY="${ANTHROPIC_PROXY:-https://claude-proxy.zhengyishen1.workers.dev}"
    fi
}

# Subcommand: check
proxy_check() {
    load_config

    local proxy_url="http://${PROXY_HOST}:${PROXY_PORT}"

    # Quick port check using nc (fast, ~10ms)
    if command -v nc &> /dev/null; then
        if nc -z -w 1 "$PROXY_HOST" "$PROXY_PORT" 2>/dev/null; then
            echo "✓ Proxy is reachable at $proxy_url"
            return 0
        else
            echo "✗ Proxy is not reachable at $proxy_url"
            return 1
        fi
    else
        # Fallback to curl if nc not available
        if timeout 2 curl -s -x "$proxy_url" -o /dev/null http://example.com 2>/dev/null; then
            echo "✓ Proxy is reachable at $proxy_url"
            return 0
        else
            echo "✗ Proxy is not reachable at $proxy_url"
            return 1
        fi
    fi
}

# Subcommand: status
proxy_status() {
    load_config

    echo "Configuration:"
    echo "  Proxy URL: http://${PROXY_HOST}:${PROXY_PORT}"
    echo "  Anthropic Base URL: ${ANTHROPIC_PROXY}"
    echo "  Config file: $CONFIG_FILE"
    echo ""

    echo "Environment variables:"
    if [ -n "$http_proxy" ]; then
        echo "  http_proxy=$http_proxy"
    else
        echo "  http_proxy=(not set)"
    fi

    if [ -n "$https_proxy" ]; then
        echo "  https_proxy=$https_proxy"
    else
        echo "  https_proxy=(not set)"
    fi

    if [ -n "$ANTHROPIC_BASE_URL" ]; then
        echo "  ANTHROPIC_BASE_URL=$ANTHROPIC_BASE_URL"
    else
        echo "  ANTHROPIC_BASE_URL=(not set)"
    fi

    echo ""
    proxy_check
}

# Subcommand: enable
proxy_enable() {
    load_config

    local proxy_url="http://${PROXY_HOST}:${PROXY_PORT}"

    export http_proxy="$proxy_url"
    export https_proxy="$proxy_url"
    export ANTHROPIC_BASE_URL="$ANTHROPIC_PROXY"

    echo "Proxy enabled:"
    echo "  http_proxy=$http_proxy"
    echo "  https_proxy=$https_proxy"
    echo "  ANTHROPIC_BASE_URL=$ANTHROPIC_BASE_URL"
}

# Subcommand: disable
proxy_disable() {
    unset http_proxy
    unset https_proxy
    unset ANTHROPIC_BASE_URL

    echo "Proxy disabled"
}

# Subcommand: init
proxy_init() {
    load_config

    local shell_type="${1:-auto}"

    # Detect shell if auto
    if [ "$shell_type" = "auto" ]; then
        if [ -n "$ZSH_VERSION" ]; then
            shell_type="zsh"
        elif [ -n "$BASH_VERSION" ]; then
            shell_type="bash"
        else
            shell_type="zsh"  # Default to zsh
        fi
    fi

    local rc_file
    case "$shell_type" in
        zsh)
            rc_file="$HOME/.zshrc"
            ;;
        bash)
            rc_file="$HOME/.bashrc"
            ;;
        *)
            echo "Error: Unknown shell type: $shell_type"
            echo "Use: claude-tools proxy init [zsh|bash]"
            exit 1
            ;;
    esac

    # Generate init snippet
    local init_snippet="# Claude Code Proxy Auto-Enable
if [ -f \"$REPO_ROOT/claude-tools/proxy/init.sh\" ]; then
    source \"$REPO_ROOT/claude-tools/proxy/init.sh\"
fi"

    # Check if already added
    if grep -q "claude-tools/proxy/init.sh" "$rc_file" 2>/dev/null; then
        echo "✓ Proxy auto-enable already configured in $rc_file"
    else
        echo ""
        echo "Add the following to your $rc_file:"
        echo ""
        echo "$init_snippet"
        echo ""
        echo "Or run this command to add it automatically:"
        echo "  echo '$init_snippet' >> $rc_file"
    fi
}

# Subcommand: config
proxy_config() {
    local action="$1"

    case "$action" in
        edit)
            ${EDITOR:-nano} "$CONFIG_FILE"
            ;;
        show)
            if [ -f "$CONFIG_FILE" ]; then
                cat "$CONFIG_FILE"
            else
                echo "No config file found at: $CONFIG_FILE"
                echo "Run 'claude-tools proxy config create' to create one"
            fi
            ;;
        create)
            if [ -f "$CONFIG_FILE" ]; then
                echo "Config file already exists at: $CONFIG_FILE"
                echo "Use 'claude-tools proxy config edit' to modify it"
            else
                cat > "$CONFIG_FILE" <<EOF
# Proxy configuration for Claude Code
# This file is sourced by the proxy tool

# Local proxy settings
PROXY_HOST="127.0.0.1"
PROXY_PORT="33210"

# Anthropic API proxy (if using custom proxy)
ANTHROPIC_PROXY="https://claude-proxy.zhengyishen1.workers.dev"
EOF
                echo "Created config file at: $CONFIG_FILE"
                echo "Edit with: claude-tools proxy config edit"
            fi
            ;;
        *)
            echo "Usage: claude-tools proxy config [show|edit|create]"
            exit 1
            ;;
    esac
}

# Show help
show_help() {
    cat <<EOF
Proxy Auto-Enable Tool for Claude Code
=======================================

Automatically enable HTTP/HTTPS proxy when VPN is connected.

USAGE:
  claude-tools proxy <command> [args...]

COMMANDS:
  check         Check if proxy is reachable
  status        Show proxy status and configuration
  enable        Enable proxy in current shell
  disable       Disable proxy in current shell
  init [shell]  Show instructions to add auto-enable to shell
  config        Manage proxy configuration (show|edit|create)
  (no args)     Show this help

PREREQUISITES:
EOF

    # Check prerequisites
    if command -v nc &> /dev/null; then
        echo "  ✓ nc (netcat)"
    else
        echo "  ⚠ nc (netcat) - recommended for faster checks"
    fi

    if command -v timeout &> /dev/null; then
        echo "  ✓ timeout"
    else
        echo "  ⚠ timeout - recommended for reliability"
    fi

    cat <<EOF

EXAMPLES:
  # Check if proxy is reachable
  claude-tools proxy check

  # Show current status
  claude-tools proxy status

  # Enable proxy manually
  claude-tools proxy enable

  # Setup auto-enable on shell startup
  claude-tools proxy init

  # Create/edit configuration
  claude-tools proxy config create
  claude-tools proxy config edit

AUTOMATIC SETUP:
  1. Create config: claude-tools proxy config create
  2. Setup auto-enable: claude-tools proxy init
  3. Add the suggested line to your ~/.zshrc or ~/.bashrc
  4. Restart terminal - proxy will auto-enable when VPN is connected!

HOW IT WORKS:
  - On shell startup, quickly checks if proxy port is listening
  - If reachable, exports http_proxy, https_proxy, ANTHROPIC_BASE_URL
  - If not reachable, skips proxy setup (zero overhead)
  - Check is fast (~10ms) so terminal startup is not delayed
EOF
}

# Main command router
main() {
    local command="$1"
    shift

    case "$command" in
        check)
            proxy_check
            ;;
        status)
            proxy_status
            ;;
        enable)
            proxy_enable
            ;;
        disable)
            proxy_disable
            ;;
        init)
            proxy_init "$@"
            ;;
        config)
            proxy_config "$@"
            ;;
        "")
            show_help
            ;;
        *)
            echo "Unknown command: $command"
            echo "Run 'claude-tools proxy' for usage"
            exit 1
            ;;
    esac
}

main "$@"
