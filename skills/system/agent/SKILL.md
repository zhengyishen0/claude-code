---
name: agent
description: Multi-framework agent launcher with unified configuration.
---

# Agent

Launches agentic coding tools (Claude Code, Open Code, Codex, etc.) with unified configuration.

## Usage

```bash
agent "prompt"                    # New session with default model
agent                             # Interactive session
agent --model sonnet "task"       # Use specific model alias
agent -r                          # Pick from recent sessions
agent -r <partial>                # Resume by partial session ID
agent -c                          # Continue last session
```

## Architecture

```
run (entry point)
 │
 ├── parses user args, loads agents/*.md
 │
 └── dispatch.sh
      │
      ├── reads config/provider.yaml
      ├── resolves model alias → framework
      ├── derives workspace prefix
      ├── exports ZENIX_* env vars
      │
      └── <framework>.sh (e.g., claude-code.sh)
           │
           ├── translates env vars to CLI flags
           │
           └── exec <command> [flags]
```

## Configuration

### config/provider.yaml

```yaml
models:
  opus:
    provider: anthropic
    model: claude-opus-4-5
    framework: claude-code

  sonnet:
    provider: anthropic
    model: claude-sonnet-4-5-20250929
    framework: claude-code

frameworks:
  claude-code:
    command: claude
    permissions:
      auto: --dangerously-skip-permissions
      prompt: --allow-dangerously-skip-permissions
    flags:
      model: --model
      system_prompt: --append-system-prompt
      add_dir: --add-dir

defaults:
  model: opus
  permissions: auto
  workspace: true
  skills: [all]
```

### agents/*.md (Subagents)

```markdown
---
name: code-reviewer
description: Reviews code for quality
model: sonnet
permissions: prompt
---

You are a senior code reviewer...
```

## Unified Interface

dispatch.sh exports these env vars for all framework parsers:

```bash
# Identity
ZENIX_SESSION_ID=a1b2c3d4
ZENIX_FRAMEWORK=claude-code

# Workspace
ZENIX_WORKSPACE_PATH=~/.workspace/cc-a1b2c3d4
ZENIX_WORKSPACE_ENABLED=true

# Model
ZENIX_MODEL_ALIAS=sonnet
ZENIX_MODEL_ID=claude-sonnet-4-5-20250929

# Behavior
ZENIX_PERMISSIONS=auto    # auto | prompt

# Content
ZENIX_SYSTEM_PROMPT="..."
ZENIX_SKILLS="work,research"
```

## Workspace Prefix

Derived from framework name:

| Pattern | Rule | Example |
|---------|------|---------|
| Multi-word | Initials | `claude-code` → `cc` |
| Single word | First + last | `codex` → `cx` |

Override with `workspace_prefix:` in provider.yaml if collision.

Result: `~/.workspace/<prefix>-<session_id>`

## Creating a Framework Parser

To add support for a new framework (e.g., `open-code`):

### 1. Add to provider.yaml

```yaml
models:
  gpt4:
    provider: openai
    model: gpt-4o
    framework: open-code

frameworks:
  open-code:
    command: opencode
    permissions:
      auto: --yes
      prompt: ""
    flags:
      model: --model
      system_prompt: --system
```

### 2. Create scripts/open-code.sh

```bash
#!/bin/bash
# Translates ZENIX_* env vars to opencode flags

ARGS=()

# Model
ARGS+=(--model "$ZENIX_MODEL_ID")

# Permissions
case "$ZENIX_PERMISSIONS" in
    auto)   ARGS+=(--yes) ;;
    prompt) ;;  # default behavior
esac

# Workspace
if [[ "$ZENIX_WORKSPACE_ENABLED" == "true" ]]; then
    ARGS+=(--cwd "$ZENIX_WORKSPACE_PATH")
fi

# System prompt
if [[ -n "$ZENIX_SYSTEM_PROMPT" ]]; then
    ARGS+=(--system "$ZENIX_SYSTEM_PROMPT")
fi

# Execute with passthrough args
exec opencode "${ARGS[@]}" "$@"
```

### 3. Make executable

```bash
chmod +x scripts/open-code.sh
```

## Permissions Modes

| Mode | Meaning |
|------|---------|
| `auto` | No permission prompts |
| `prompt` | Ask before risky actions |

Each framework translates these to its own flags.

## Session Management

```bash
agent -r                    # List recent sessions
agent -r abc123             # Resume by partial ID
agent -c                    # Continue last session

# Direct script access
scripts/session.sh find <partial>
scripts/session.sh list [n]
```

## Passthrough

Unknown flags pass directly to the framework:

```bash
agent --verbose "debug this"
agent -p "custom prompt" "task"
```
