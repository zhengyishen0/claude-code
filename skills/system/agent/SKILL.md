---
name: agent
description: Claude Code wrapper with preconfigured model, permissions, profiles, and session management.
---

# Agent

Replaces `cc` - launches Claude Code with settings from `config/agents.yaml`.

## Usage

```bash
agent "prompt"              # New session with config defaults
agent                       # Interactive session
agent -r                    # Pick from recent sessions (shows summaries)
agent -r <partial>          # Resume by partial session ID
agent -c                    # Continue last session
agent -P <profile> "prompt" # Use named profile
```

## Session Management

Find and list sessions by partial ID:

```bash
# List recent sessions (current project)
agent -r

# Resume by partial ID
agent -r abc123

# Direct script access
scripts/session.sh find <partial>          # Returns full session ID
scripts/session.sh find <partial> --path   # Also show file path
scripts/session.sh list [n]                # List recent n sessions
```

## Profiles

```yaml
# config/agents.yaml
defaults:
  model: claude-opus-4-5
  permissions: auto

profiles:
  research:
    model: claude-opus-4-6
    permissions: default
    system_prompts:
      - prompts/research.md

  quick:
    model: claude-haiku-4-5-20251001
    permissions: auto
```

Use with: `agent -P research "deep dive into..."`

## Overrides

```bash
agent --model claude-haiku-4-5-20251001 "quick task"
agent --permissions default "be careful"
```

## Permissions Modes

| Mode | Flag | Behavior |
|------|------|----------|
| `auto` | `--dangerously-skip-permissions` | No prompts |
| `default` | `--allow-dangerously-skip-permissions` | Prompts, can bypass |

## System Prompts

Multiple files concatenated in order. Paths relative to `config/` or absolute:

```yaml
system_prompts:
  - prompts/base.md
  - prompts/project.md
```

## Skills

Inject SKILL.md content into system prompt. Supports:

```yaml
skills:
  - all              # All skills
  - core             # All skills in core/
  - vault            # Specific skill by name
  - core/vault       # Specific skill by path
```

Uses `skill content <target>` under the hood.

## Passthrough

Unknown flags pass directly to claude:

```bash
agent -p "custom prompt" "task"
agent --verbose "debug this"
```
