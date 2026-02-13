---
name: proxy
description: Proxy management for network and Anthropic API routing
---

# proxy

Manage HTTP proxy settings for network access and Anthropic API routing.

## Usage

```bash
proxy status        # Show proxy status and environment
proxy check         # Check if proxy is reachable
proxy config        # Manage config (show|edit|create)
```

## Auto-init

Proxy auto-enables on shell startup if reachable (via env.sh).
