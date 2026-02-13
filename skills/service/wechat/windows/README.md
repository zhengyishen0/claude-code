# WeChat Windows Tools

A toolkit for extracting and decrypting WeChat databases on Windows.

## Requirements

- Windows 10/11 (64-bit)
- Python 3.10+
- WeChat 4.x (Weixin.exe)
- Administrator privileges (for key extraction)

## Quick Start

### Install dependencies

```batch
pip install pycryptodome zstandard
```

### Usage

All commands use a single entry point:

```batch
wechat <command> [options]
```

Or with Python directly:
```batch
python wechat.py <command> [options]
```

### Commands

| Command | Description |
|---------|-------------|
| `wechat` | Check status (has key? synced?) |
| `wechat check` | Same as above |
| `wechat extract` | Extract encryption key (requires Admin) |
| `wechat sync` | Sync and decrypt latest databases |
| `wechat search <query>` | Search messages |
| `wechat search --contacts` | List all contacts |
| `wechat account` | Show current account info |
| `wechat account --list` | List all accounts |
| `wechat account --switch <wxid>` | Switch active account |
| `wechat account --name <nickname>` | Set nickname for current account |

### Typical Workflow

```batch
# 1. First time: extract the key (will prompt for admin)
wechat extract

# 2. Sync databases (decrypt to local)
wechat sync

# 3. Search messages
wechat search "keyword"
wechat search --contacts
```

If no key exists, running `wechat` or `wechat sync` will automatically start extraction.

## Multi-Account Support

The tool supports multiple WeChat accounts. Keys are stored per-account:

```batch
# List all accounts
wechat account --list

# Switch between accounts
wechat account --switch wxid_xxxxx

# Set a friendly name
wechat account --name "Work Account"
```

## Files

| File | Description |
|------|-------------|
| `wechat.py` | Unified CLI tool |
| `wechat.bat` | Batch launcher |
| `wechat_config.json` | Saved keys and settings (gitignored) |
| `bin/wx_key.dll` | Key extraction DLL |
| `bin/wechat-dump-rs.exe` | Decryption tool |

## Database Locations

| Platform | Path |
|----------|------|
| Windows 4.x | `%USERPROFILE%\xwechat_files\wxid_XXX\db_storage\message\` |
| Windows 3.x | `%USERPROFILE%\Documents\WeChat Files\wxid_XXX\Msg\` |

## Notes

- **Windows only**: The key extraction uses Windows-specific DLLs
- **WeChat 4.x**: Tested with WeChat 4.1.x (Weixin.exe)
- **Admin required**: Key extraction needs admin to read WeChat's memory
- **Key is account-specific**: Same key works across PCs for the same account
- **Key is platform-specific**: Windows key only works for Windows databases

## Credits

- [wx_key](https://github.com/ycccccccy/wx_key) - Key extraction DLL
- [wechat-dump-rs](https://github.com/0xlane/wechat-dump-rs) - Database decryption

## Disclaimer

For educational and personal backup purposes only.
