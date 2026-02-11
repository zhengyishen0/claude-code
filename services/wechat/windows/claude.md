# WeChat Tool

CLI for searching WeChat messages on Windows. Supports multiple accounts.

## When to Use

User mentions: WeChat, 微信, messages, chat history, contacts, conversations

## Commands

```bash
wechat                              # Show accounts + help
wechat account                      # Show accounts only
wechat login                        # Login new account (requires admin)
wechat sync                         # Decrypt databases (incremental)
wechat search "query"               # Search all accounts
wechat search --account 李老师 "q"   # Search specific account
wechat search --chats               # List all chats
wechat search --chats --account 李  # List chats in specific account
```

## Search Syntax

```bash
"托福"                    # Simple keyword
"越媛: 学习"              # Search in contact's chat (colon separator)
"托福 写作"               # OR logic (either term)
"+托福 +写作"             # AND logic (both terms)
```

## How to Run

Use PowerShell for Chinese text:
```bash
powershell.exe -Command "cd 'E:\Downloads\wechat-windows-tools'; python wechat.py <command>"
```

## Quick Reference

| User Request | Command |
|--------------|---------|
| Find messages about X | `search "X"` |
| Find X in 李老师's account | `search --account 李老师 "X"` |
| What did 越媛 say about X | `search "越媛: X"` |
| List all chats | `search --chats` |
| List chats in specific account | `search --chats --account 李老师` |
| What accounts exist | `account` |
| Get latest messages | `sync` then search |

## Notes

- `sync` before searching if user wants "latest" or "recent" messages
- Don't run `login` - requires admin + user interaction
- Search defaults to all accounts unless `--account` specified
- `--account` accepts partial nickname match
