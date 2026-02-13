---
name: feishu
description: Feishu/Lark APIs (Messaging, Calendar, Bitable, VC). Use when user needs to access Feishu services, send messages, manage calendar, or work with Bitable.
---

# Feishu API

Access Feishu/Lark services via CLI.

## Commands

```bash
service feishu status                    # Check auth status
service feishu admin                     # One-time setup
service feishu domains                   # List available domains
service feishu <domain> <action> [args...]
```

## Available Domains

| Domain | Purpose |
|--------|---------|
| im | Messaging (send, receive, search) |
| calendar | Calendar events |
| bitable | Bitable (spreadsheet-like database) |
| vc | Video conferencing |
| contact | Contacts and users |
| drive | Cloud documents |

## Examples

```bash
# Messaging
service feishu im send --chat "Group Name" "Hello!"
service feishu im search "keyword"

# Calendar
service feishu calendar list
service feishu calendar create "Meeting" --time "2024-02-10 14:00"

# Bitable
service feishu bitable list
service feishu bitable records APP_TOKEN TABLE_ID
```

## Bot Mode

```bash
service feishu bot start                 # Start bot listener
service feishu bot start --cc            # Start with Claude Code integration
service feishu bot status                # Check bot status
```

## First Time Setup

1. Create app on Feishu Open Platform
2. Run `service feishu admin`
3. Enter App ID and App Secret
4. Configure permissions in Feishu console
