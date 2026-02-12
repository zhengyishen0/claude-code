---
name: hook
description: Claude Code hooks management with auto-discovery
---

# Hook

Manages Claude Code hooks with YAML config and auto-discovery.

## Structure

```
skills/*/hooks/
├── settings.yaml    # Hook config for this skill
└── *.sh             # Hook scripts

skills/hook/
├── hooks/           # Non-skill hooks
│   ├── settings.yaml
│   └── persist-env.sh
├── scripts/
│   └── build.sh     # Rebuild .claude/settings.json
└── watch/
    └── hook.yaml    # Auto-rebuild watcher
```

## Usage

```bash
# Manual rebuild
skills/hook/scripts/build.sh

# Start watcher (auto-rebuild on change)
skills/watcher/run.sh start hook-builder

# Check status
skills/watcher/run.sh status
```

## Creating Hooks

Add `hooks/settings.yaml` to any skill:

```yaml
- event: PreCompact
  script: precompact.sh
  timeout: 60  # optional

- event: SessionEnd
  script: session-end.sh
```

**Events:** SessionStart, UserPromptSubmit, SubagentStart, PostToolUse, PreCompact, SessionEnd, etc.

**Script path:** Relative to the skill's `hooks/` folder.

## How It Works

1. `build.sh` scans all `skills/*/hooks/settings.yaml`
2. Merges hooks into `.claude/settings.json`
3. Preserves non-hook settings (env, statusLine, effortLevel)
4. Watcher auto-runs build on any settings.yaml change
