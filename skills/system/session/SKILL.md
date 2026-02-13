---
name: session
description: Find Claude sessions by partial ID. Use when you need to look up or resume a previous session.
---

# Session Skill

Find Claude sessions by partial ID match.

## CLI Usage

```bash
session find <partial>          # Returns full session ID
session find <partial> --path   # Also returns file path
session list [n]                # List recent n sessions
```

## Examples

```bash
# Find session by partial ID
session find abc123
# Output: abc123-def4-5678-90ab-cdef12345678

# Get session ID and file path
session find 4ee9 --path
# Output:
# 4ee9c522-4a96-4df3-abc4-88b5c15105b6
# /Users/.../.claude/projects/.../4ee9c522-....jsonl

# List recent sessions
session list 5
```

## Used By

- `cc -r <partial>` - Resume session by partial ID
- Other scripts needing session lookup
