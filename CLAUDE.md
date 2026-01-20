# Claude Code

## Workflow

Main branch is protected. Create a worktree before making changes:

```bash
worktree create feature-name     # Create branch + worktree
# ... make changes using absolute paths ...
worktree cleanup feature-name    # Merge, remove worktree, delete branch
```

Keep the tree clean:
- Stage changes promptly: `git add <file>`
- Revert unwanted changes: `git checkout <file>`
- Remove test/temp files: `rm <file>`
- Commit when a logical unit of work is complete

## Tools

`browser` `memory` `world` `worktree` `supervisor` `api` `screenshot` `proxy`

Run any tool without arguments for help.
