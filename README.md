# Claude Code

Local development tools for AI-assisted workflows.

## Tools

Run any tool without args for help:

| Tool | Description |
|------|-------------|
| `browser` | Browser automation with CDP |
| `memory` | Cross-session knowledge sharing |
| `world` | Agent coordination log |
| `worktree` | Git worktree management |
| `screenshot` | Background window capture |
| `proxy` | Auto-enable proxy when VPN connected |

## Structure

```
claude-code/
├── browser/       # Browser automation (CDP)
├── memory/        # Cross-session search & recall
├── world/         # Agent coordination (world.log)
├── worktree/      # Git worktree management
├── tools/         # Additional tools (screenshot, proxy)
├── voice/         # Voice pipeline (transcription, speaker ID)
├── docs/          # Design documents
├── CLAUDE.md      # Instructions for AI
└── TODO.md        # Future plans
```

## Setup

```bash
# Install dependencies
brew bundle install

# Reload shell for aliases
source ~/.zshrc
```
