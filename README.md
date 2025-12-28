# Claude Code Project

Local development environment with browser automation and AI tooling.

## Documentation

- **[Progressive Help Design](progressive-help-design.md)** - Design decisions for the progressive help system (metadata-driven tool documentation)
- **[Chrome Profile Security](PROFILE-STRATEGY.md)** - Best practices for Chrome profile management and cloud deployment

## Quick Start

```bash
# First-time setup
claude-tools init

# Update tool documentation
claude-tools sync
```

## Project Structure

```
claude-code/
├── claude-tools/          # CLI utilities
│   ├── chrome/           # Browser automation
│   ├── documentation/    # External docs access
│   ├── environment/      # Event log for multi-agent
│   ├── memory/           # Cross-session knowledge
│   ├── screenshot/       # Window capture
│   └── worktree/         # Git worktree management
├── claude-manager/       # Event processing daemon
└── CLAUDE.md            # Project instructions for AI
```

## Tools

Run `claude-tools <tool>` for help on any tool:

- **chrome** - Browser automation with CDP
- **documentation** - Get library docs, CLI examples, API specs
- **environment** - Event log for persistent collaboration
- **memory** - Search and consult previous sessions
- **screenshot** - Background window capture
- **worktree** - Git worktree management

See [claude-tools/README.md](claude-tools/README.md) for details.
