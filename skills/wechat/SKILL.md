---
name: wechat
description: Search WeChat messages and chat history. Use when user mentions WeChat, 微信, or asks about messages, contacts, or conversations.
---

# WeChat Tool

Search WeChat messages across multiple accounts.

## Commands

```bash
wechat                              # Show accounts + help
wechat account                      # List accounts
wechat sync                         # Refresh database (run before searching for "latest")
wechat search "query"               # Search all accounts
wechat search --account NAME "q"    # Search specific account
wechat search --chats               # List all chats
wechat search --chats --account X   # List chats in account
```

## Search Syntax

```bash
"托福"                    # Simple keyword
"越媛: 学习"              # Search in contact's chat (colon separator)
"托福 写作"               # OR logic (either term)
"+托福 +写作"             # AND logic (both terms)
```

## Quick Reference

| User Request | Command |
|--------------|---------|
| Find messages about X | `wechat search "X"` |
| Find X in account | `wechat search --account 李老师 "X"` |
| What did 越媛 say about X | `wechat search "越媛: X"` |
| List all chats | `wechat search --chats` |
| What accounts exist | `wechat account` |
| Get latest messages | `wechat sync` then search |

## Notes

- Run `sync` before searching if user wants "latest" or "recent" messages
- `--account` accepts partial nickname match
- Don't run `login` - requires admin + user interaction
