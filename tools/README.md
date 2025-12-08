# Tools

Collection of utilities for development workflows.

## Universal Entry Point

```bash
tools/run.sh <tool> [command] [args...]
```

## Available Tools

### [chrome](chrome/README.md)

Browser automation with React/SPA support

**Quick Start:**
```bash
tools/chrome/run.sh open "https://example.com"
tools/chrome/run.sh recon
tools/chrome/run.sh click '[data-testid="btn"]' + wait + recon
```

**Key Commands:** `recon`, `open`, `wait`, `click`, `input`, `esc`

[Full documentation →](chrome/README.md)

### [worktree](worktree/README.md)

Git worktree management for isolated feature development

**Quick Start:**
```bash
tools/worktree/run.sh create feature-name  # Create worktree + launch Claude
tools/worktree/run.sh list                 # List all worktrees
tools/worktree/run.sh remove feature-name  # Remove worktree
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
tools/chrome/run.sh          # Show help + check prerequisites
tools/chrome/run.sh help     # Show help
tools/worktree/run.sh help   # Show help
```
