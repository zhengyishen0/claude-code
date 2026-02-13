---
name: skill
description: How to create reusable, inter-powering skills
---

# Skill

How to create reusable, inter-powering skills.

## Structure

```
skills/<name>/
├── SKILL.md              # Context for AI (required)
├── run.sh                # Main entry point
├── config/               # YAML configuration files
├── watch/*.yaml          # Triggers (auto-discovered by watcher)
├── hooks/*.sh            # Claude Code lifecycle hooks
├── prompts/              # AI system prompts for sub-sessions
├── templates/            # Document templates
├── scripts/              # Standalone executables
├── lib/                  # Shared code (sourced, not executed)
└── data -> ~/.zenix/data/<name>/   # Symlink to persistent storage
```

## Layers

| File | Purpose | Discovery |
|------|---------|-----------|
| SKILL.md | AI context when `/skill` invoked | By name |
| run.sh | CLI entry point | Manual or by other skills |
| watch/*.yaml | Event triggers | Auto by `skills/watcher/run.sh` |
| hooks/*.sh | Claude Code lifecycle | Via `.claude/settings.json` |

## Data Convention

```bash
mkdir -p ~/.zenix/data/<name>
ln -s ~/.zenix/data/<name> skills/<name>/data
```

Scripts use relative `./data` — portable, no hardcoded paths.

| Location | Contains | In Git |
|----------|----------|--------|
| `skills/<name>/` | Code, config, prompts | Yes |
| `~/.zenix/data/<name>/` | Runtime data, state | No |
| `skills/<name>/data` | Symlink | Yes (link only) |

## SKILL.md Format

```markdown
---
name: skill-name
description: One-line for skill list
---

# Skill Name

What this skill does.

## Usage
## Commands
## Configuration
```

## Watcher (watch/*.yaml)

```yaml
name: unique-watcher-name
type: fswatch | cron

# fswatch
path: relative/path/
events: [Created, Updated]
exclude: [\.DS_Store]
debounce: 15
rules:
  - match: ^pattern\.md$
    action: scripts/handler.sh

# cron
schedule: "*/30 * * * *"
action: scripts/periodic.sh
```

## Inter-Skill Communication

1. **Watcher** — skill defines `watch/*.yaml`, `watcher` runs it
2. **Sub-sessions** — skill calls `claude -p` with `prompts/*.md`
3. **Shared data** — skills read/write to known paths
4. **Scripts** — one skill calls another's `scripts/`

## Creating a New Skill

```bash
mkdir -p skills/<name>/{scripts,prompts,templates}

cat > skills/<name>/SKILL.md << 'EOF'
---
name: <name>
description: What it does
---
# <Name>
...
EOF

# Data (if needed)
mkdir -p ~/.zenix/data/<name>
ln -s ~/.zenix/data/<name> skills/<name>/data

# Watcher (if needed)
mkdir -p skills/<name>/watch
```

## Examples

| Skill | Demonstrates |
|-------|--------------|
| vault | watch + prompts + scripts + templates |
| watcher | auto-discovery + central runner |
| memory | data symlink + run.sh |
| daily | hooks (precompact, session-end) |
