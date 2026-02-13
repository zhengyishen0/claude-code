---
name: memory
description: Search and recall from previous Claude Code sessions. Use when user asks about past conversations, previous work, or needs to find something discussed before.
---

# Memory Tool

Search across all Claude Code sessions like a hive mind.

## Commands

```bash
# Search for sessions (start here)
memory search "keyword1 keyword2"

# If snippets aren't enough, recall with a question
memory search "keywords" --recall "specific question?"
```

## Search Modes

**Simple mode** (default): Space-separated keywords, OR logic, ranked by matches
```bash
memory search "chrome automation workflow"
```

**Strict mode** (pipes): AND between groups, OR within groups
```bash
memory search "chrome|browser automation|workflow"
```

## Options

- `--sessions N` - Number of sessions (default: 10)
- `--messages N` - Messages per session (default: 5)
- `--recall "question"` - Ask the matching sessions a question

## When to Use

- User asks: "What did we discuss about X?"
- User asks: "How did we solve Y before?"
- User asks: "Find that session where we..."
- Need context from previous work

## Key Principle

**Search first, recall second.** Snippets often contain enough info. Only use `--recall` when you need deeper synthesis.
