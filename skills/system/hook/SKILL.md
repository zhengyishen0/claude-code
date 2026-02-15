---
name: hook
description: Claude Code hooks management with auto-discovery
---

# Hook

Manages Claude Code hooks with YAML config and auto-discovery.

## Commands

```bash
zenix hook list              # List all registered hooks
zenix hook list --event Pre  # Filter by event name
zenix hook list --json       # Output as JSON
zenix hook build             # Rebuild .claude/settings.json
```

## Structure

```
skills/<category>/<skill>/hooks/
├── settings.yaml    # Hook config for this skill
└── *.sh             # Hook scripts

skills/system/hook/
├── hooks/           # Infrastructure hooks
│   ├── settings.yaml
│   └── persist-env.sh
├── scripts/
│   ├── build.sh     # Rebuild .claude/settings.json
│   └── list.sh      # List all hooks
└── watchers/
    └── hook.yaml    # Auto-rebuild watcher
```

## Creating Hooks

Add `hooks/settings.yaml` to any skill:

```yaml
- event: PreCompact
  script: precompact.sh
  timeout: 60           # optional, seconds
  description: Brief description for zenix hook list

- event: PostToolUse
  matcher: Edit|Write   # optional, tool filter regex
  script: my-hook.sh
  description: Runs after Edit or Write tools
```

### Fields

| Field | Required | Description |
|-------|----------|-------------|
| event | yes | Hook event (SessionStart, PreToolUse, etc.) |
| script | yes | Script path relative to hooks/ folder |
| matcher | no | Tool name regex filter |
| timeout | no | Max execution time in seconds |
| description | no | Brief description for `zenix hook list` |

### Events

- `SessionStart` - When session begins
- `SessionEnd` - When session ends
- `SubagentStart` - When subagent spawns
- `UserPromptSubmit` - When user sends a message
- `PreToolUse` - Before a tool executes
- `PostToolUse` - After a tool executes
- `PreCompact` - Before context compaction

## How It Works

1. `build.sh` scans all `skills/*/*/hooks/settings.yaml`
2. Merges hooks into `.claude/settings.json`
3. Preserves non-hook settings (env, statusLine, effortLevel)
4. Watcher auto-runs build on any settings.yaml change
