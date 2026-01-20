# Proxy Tool

Auto-enables proxy when VPN is connected.

## Setup

Source `shell-init.sh` in your `~/.zshrc` (includes proxy auto-init):

```bash
source ~/Codes/claude-code/shell-init.sh
```

Or manually add:

```bash
# Proxy alias
alias proxy="$PROJECT_DIR/tools/proxy/run.sh"

# Auto-enable proxy on shell startup
source "$PROJECT_DIR/tools/proxy/init.sh"
```

## Commands

```bash
proxy check     # Check if proxy is reachable
proxy status    # Show current status
proxy config    # Manage config (show|edit|create)
```

## Manual Toggle

Shell functions (defined by init.sh):

```bash
proxy_on        # Enable proxy
proxy_off       # Disable proxy
```

## How It Works

On every shell startup:
1. Quick check if proxy port is listening (~10ms)
2. If reachable → export `http_proxy`, `https_proxy`, `ANTHROPIC_BASE_URL`
3. If not reachable → skip (zero overhead)
