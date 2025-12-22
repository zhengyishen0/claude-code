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

1. **No args = help** - Running a tool without arguments shows help (no `--help` or `help` subcommand)
2. **README for details** - Brief help in CLI, comprehensive docs in README.md
3. **Standard entry point** - Each tool uses `run.sh`, name derived from folder

## Getting Help

Run any tool without arguments:

```bash
claude-tools chrome          # Show help
claude-tools worktree        # Show help
claude-tools memory          # Show help
```
