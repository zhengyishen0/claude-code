---
name: service
description: Unified entry point for external service APIs. Use /google or /feishu for specific services.
---

# Service Command

Unified CLI for external service APIs.

## Command

```bash
service --list              # List available services
service google ...          # Google APIs (see /google)
service feishu ...          # Feishu APIs (see /feishu)
```

## Available Services

| Service | Skill | Description |
|---------|-------|-------------|
| google | /google | Gmail, Calendar, Drive, Sheets |
| feishu | /feishu | Messaging, Calendar, Bitable, VC |

## Usage

For detailed usage, use the specific skill:
- `/google` - Google API documentation
- `/feishu` - Feishu API documentation

## Examples

```bash
service --list
service google auth
service google gmail users.messages.list userId=me
service feishu status
service feishu im send --chat "Group" "Hello"
```
