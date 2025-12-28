# Proxy Auto-Enable

Automatically enable HTTP/HTTPS proxy when VPN is connected - no manual toggling needed!

## Commands

### check
Check if proxy is reachable at configured host:port

### status
Show current proxy configuration and environment variable status

### enable
Manually enable proxy in current shell session

### disable
Manually disable proxy in current shell session

### init
Show instructions to add auto-enable to shell startup (~/.zshrc or ~/.bashrc)

### config
Manage proxy configuration file (.proxy-config)
- `config show` - Display current configuration
- `config edit` - Edit configuration in $EDITOR
- `config create` - Create default configuration file

## Setup

**One-time setup** (run once per project):

```bash
# 1. Create configuration file
claude-tools proxy config create

# 2. Get shell initialization instructions
claude-tools proxy init

# 3. Add the suggested line to your ~/.zshrc or ~/.bashrc
# Example: echo 'source /path/to/claude-code/claude-tools/proxy/init.sh' >> ~/.zshrc

# 4. Restart your terminal - proxy will auto-enable when VPN is connected!
```

## How It Works

On every terminal startup:
1. Quick check if proxy port is listening (~10ms using netcat)
2. If reachable → export `http_proxy`, `https_proxy`, `ANTHROPIC_BASE_URL`
3. If not reachable → skip proxy setup (zero overhead)

No manual proxy toggling needed - it's automatic!

## Configuration

Edit `.proxy-config` in repository root:

```bash
# Local proxy settings
PROXY_HOST="127.0.0.1"
PROXY_PORT="33210"

# Anthropic API proxy
ANTHROPIC_PROXY="https://claude-proxy.zhengyishen1.workers.dev"
```

## Key Principles

1. **Zero overhead when disconnected** - Fast port check (~10ms) doesn't slow down terminal startup
2. **Automatic activation** - Works for every new terminal instance without manual intervention
3. **VPN-aware** - Only enables when proxy is actually reachable
4. **Project-local config** - Configuration stored in repo, can be gitignored or shared with team
5. **Manual override available** - Use `enable`/`disable` commands for one-off changes
