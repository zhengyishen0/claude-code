---
name: jj
description: jj (Jujutsu) version control - NOT git. Use this skill when working with version control in this codebase. Critical differences from git.
---

# jj (NOT git)

This codebase uses jj, not git. Key differences:

## Quick Reference

| Task | git | jj |
|------|-----|-----|
| Status | `git status` | `jj status` |
| Diff | `git diff` | `jj diff` |
| Log | `git log` | `jj log` |
| Commit | `git add . && git commit -m "msg"` | `jj new -m "msg"` |
| Amend | `git commit --amend` | `jj describe -m "msg"` |
| Branch | `git branch` | `jj bookmark` |
| Push | `git push` | `jj git push` |

## Critical Difference

```bash
jj describe -m "msg"     # Update CURRENT commit message (changes stay here)
jj new -m "msg"          # Create NEW commit, changes stay in parent
```

**Common mistake:** Using `jj new` when you meant `jj describe`, or vice versa.

## Recording Progress

Use commit messages as progress reports:

```bash
jj new -m "[validation] researching options"
jj new -m "[execution] implementing feature"
jj new -m "[done] verified and complete"
```

**Types:** `[validation]` `[decision]` `[execution]` `[done]` `[dropped]`

## Workspaces (Isolation)

```bash
jj workspace add ../my-workspace    # Create isolated workspace
jj workspace list                   # List workspaces
jj workspace forget NAME            # Remove workspace
```

## Safe Operations

```bash
jj abandon                          # Discard current changes safely
jj undo                            # Undo last operation
jj restore --from @-               # Restore file from parent
```

## Rules for AI

1. **New phase = new commit** with `jj new -m "[phase] description"`
2. **Same phase = update** with `jj describe -m "updated msg"`
3. **Never edit untitled node** - always know what you're working on
4. **Check before edit**: `jj log -r @` to see current commit
