# claude-tools

Collection of CLI utilities for development workflows.

## Universal Entry Point

```bash
claude-tools <tool> [command] [args...]
```

## Available Tools

### [chrome](chrome/README.md)

Browser automation with React/SPA support

**Quick Start:**
```bash
claude-tools chrome open "https://example.com"
claude-tools chrome recon
claude-tools chrome click '[data-testid="btn"]' + wait + recon
```

**Key Commands:** `recon`, `open`, `wait`, `click`, `input`, `esc`

[Full documentation →](chrome/README.md)

### [worktree](worktree/README.md)

Git worktree management for isolated feature development

**Quick Start:**
```bash
claude-tools worktree create feature-name  # Create worktree + launch Claude
claude-tools worktree list                 # List all worktrees
claude-tools worktree remove feature-name  # Remove worktree
```

**Key Commands:** `create`, `rename`, `list`, `remove`

[Full documentation →](worktree/README.md)

## Tool Design Principles

1. **Self-documenting** - Tools document themselves via `help` command
2. **Help as default** - Running with no args shows help + prereq check
3. **README for details** - Brief help in CLI, comprehensive docs in README.md
4. **Prereq check on first use** - Tools check/install dependencies when run without args
5. **Standard entry point** - Each tool uses `run.sh`, name derived from folder

## Getting Help

Run any tool without arguments or with `help`:

```bash
claude-tools chrome          # Show help + check prerequisites
claude-tools chrome help     # Show help
claude-tools worktree help   # Show help
```
