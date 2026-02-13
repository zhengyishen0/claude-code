---
name: agent
description: Claude Code wrapper with preconfigured model, permissions, and session management.
---

# Agent

Launches Claude Code with settings from `config/agents.yaml`.

## Usage

```bash
agent "prompt"              # New session with 'default' setting
agent                       # Interactive session
agent -r                    # Pick from recent sessions
agent -r <partial>          # Resume by partial session ID
agent -c                    # Continue last session
agent -P <setting> "prompt" # Use named setting
```

## Settings

```yaml
# config/agents.yaml
settings:
  default:
    model: claude-opus-4-5
    permissions: auto
    # system_prompts:
    #   - prompts/base.md
    # skills:
    #   - work

  custom:
    model: claude-opus-4-5
    permissions: default
    # system_prompts:
    #   - prompts/custom.md
```

Use with: `agent -P custom "task"`

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

## Session Management

```bash
agent -r                    # List recent sessions
agent -r abc123             # Resume by partial ID

# Direct script access
scripts/session.sh find <partial>
scripts/session.sh list [n]
```

## System Prompts

Multiple files concatenated in order. Paths relative to `config/`:

```yaml
system_prompts:
  - prompts/base.md
  - prompts/project.md
```

## Skills Injection

Inject SKILL.md content into system prompt:

```yaml
skills:
  - all              # All skills
  - system           # All skills in system/
  - work             # Specific skill by name
```

## Passthrough

Unknown flags pass directly to claude:

```bash
agent -p "custom prompt" "task"
agent --verbose "debug this"
```
