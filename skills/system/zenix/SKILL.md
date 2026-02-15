---
name: zenix
description: Unified CLI dispatcher. MUST READ when creating new skills.
---

# zenix

Unified command dispatcher for the zenix skill system.

## Usage

```bash
zenix                    # List available skills
zenix list               # Same as above
zenix <skill> [args]     # Run a skill
zenix create <name>      # Create new skill in custom/
zenix doctor [name]      # Validate skill conventions
```

## Setup

Add to PATH (one-time):

```bash
export PATH="$HOME/.zenix/bin:$PATH"
```

## Examples

```bash
zenix                    # See all available skills
zenix work on "task"     # Start working on a task
zenix browser open       # Open browser
zenix create my-tool     # Create new skill
zenix doctor             # Check all skills
zenix doctor vault       # Check specific skill
```

---

# Creating Skills

## Structure

Skills live in `~/.zenix/skills/<category>/<name>/` (repo is symlinked to `~/.zenix`).

```
skills/<category>/<name>/
├── SKILL.md              # Context for AI (required)
├── run.sh                # Main entry point
├── config/               # YAML configuration files
├── watchers/*.yaml          # Triggers (auto-discovered by watcher)
├── hooks/*.sh            # Claude Code lifecycle hooks
├── prompts/              # AI system prompts for sub-sessions
├── templates/            # Document templates
├── scripts/              # Standalone executables
├── lib/                  # Shared code (sourced, not executed)
└── data -> ~/.zenix/data/<name>/   # Symlink to persistent storage
```

**Categories:**

| Category | Location | Tracking |
|----------|----------|----------|
| `system` | Monorepo | Core functionality, always present |
| `core` | Monorepo | Essential skills, always present |
| `community` | Submodules | Distributable skills, `zenix-<name>` repos |

## Layers

| File | Purpose | Discovery |
|------|---------|-----------|
| SKILL.md | AI context when `/skill` invoked | By name |
| run.sh | CLI entry point | Via `zenix <skill>` |
| watchers/*.yaml | Event triggers | Auto by watcher |
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

## Config (config/*.yaml)

Skill-specific configuration. Format varies by skill, but typically:

```yaml
# config/settings.yaml
enabled: true
options:
  key: value
```

Scripts read config via: `yq '.options.key' "$SCRIPT_DIR/config/settings.yaml"`

## Watchers (watchers/*.yaml)

```yaml
name: unique-watcher-name
description: Brief description for zenix watcher list
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

## List Format (lib/list-format.sh)

Unified list formatter for consistent output across skills.

**Input:** TSV via stdin (group, name, tag, description)

```bash
# Usage
source "$ZENIX_ROOT/skills/system/zenix/lib/list-format.sh"
printf '%s\t%s\t%s\t%s\n' "skill" "name" "tag" "description" | list_format --group
```

**Styles:**
- `--group` (default): Group by first column with `[group]` headers
- `--inline`: Flat list with `[group]` inline after name

**Output format:**
```
[group]
name (tag): description
```

## Inter-Skill Communication

1. **Watcher** — skill defines `watchers/*.yaml`, `watcher` runs it
2. **Sub-sessions** — skill calls `claude -p` with `prompts/*.md`
3. **Shared data** — skills read/write to known paths
4. **Scripts** — one skill calls another's `scripts/`

## Community Skills (Submodules)

Community skills are separate repos, tracked as git submodules.

**Naming:** `zenix-<skill>` (e.g., `zenix-wechat`, `zenix-feishu`)

### Adding a Community Skill

```bash
git submodule add https://github.com/user/zenix-<skill>.git skills/community/<skill>
```

### Working on a Community Skill

```bash
cd skills/community/<skill>     # Submodule has its own jj
jj new                          # Create work commit
# ... make changes ...
jj commit -m "description"
jj git push                     # Push to zenix-<skill> repo
```

### Updating Submodule Pointer (in parent)

```bash
cd "$(work on 'bump skill')"    # Workspace in parent repo
cd skills/community/<skill>
git pull origin master
cd ../..                        # Back to workspace root
work done "bump <skill>"        # Commits new pointer
```

## Skill Examples

| Skill | Demonstrates |
|-------|--------------|
| vault | watch + prompts + scripts + templates |
| watcher | auto-discovery + central runner |
| memory | data symlink + run.sh |
| daily | hooks (precompact, session-end) |
| wechat | community submodule |
