# tools

Collection of CLI utilities for development workflows.

## Universal Entry Point

```bash
<tool> [command] [args...]
```

## Available Tools

### [chrome](chrome/README.md)

Browser automation with React/SPA support

**Quick Start:**
```bash
chrome open "https://example.com"
chrome recon
chrome click '[data-testid="btn"]' + wait + recon
```

**Key Commands:** `recon`, `open`, `wait`, `click`, `input`, `esc`

[Full documentation →](chrome/README.md)

### [worktree](worktree/README.md)

Git worktree management for isolated feature development

**Quick Start:**
```bash
worktree create feature-name  # Create worktree + launch Claude
worktree list                 # List all worktrees
worktree remove feature-name  # Remove worktree
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
chrome          # Show help
worktree        # Show help
memory          # Show help
```
