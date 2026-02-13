---
name: watcher
description: Auto-discovery watcher system using yaml configuration.
---

# Watcher

## Quick Start

```bash
# List discovered watchers
skills/watcher/run.sh list

# Start all watchers
skills/watcher/run.sh start

# Check status
skills/watcher/run.sh status

# Stop all watchers
skills/watcher/run.sh stop
```

## Architecture

```
skills/
├── core/
│   └── vault/
│       └── watch/
│           └── files.yaml      # Watcher config
├── apps/
│   └── feishu/
│       └── watch/
│           └── notifications.yaml
└── system/
    └── watcher/
        ├── SKILL.md            # This file
        └── run.sh              # Central runner
```

Watchers are auto-discovered from: `skills/*/*/watch/*.yaml`

State is stored in: `~/.local/state/watchers/`
- `pids/` - PID files for running watchers
- `logs/` - Log files

## Creating a Watcher

Create a yaml file in `skills/<category>/<skill>/watch/<name>.yaml`:

### fswatch (File Watching)

```yaml
name: my-watcher
type: fswatch
path: some/directory/
events: [Created, Updated, AttributeModified, Renamed]
exclude:
  - "\.DS_Store"
  - "\.git"
debounce: 15

rules:
  # Match files, optionally exclude, run action
  - match: "^.*\\.md$"
    exclude: "^README\\.md$"
    action: skills/my-skill/scripts/handle.sh

  # Conditional rule (only runs if condition succeeds)
  - match: "^tasks/.*\\.md$"
    condition: "grep -q '^ready: true'"
    action: skills/my-skill/scripts/process.sh
```

**Fields:**
- `name`: Unique watcher identifier
- `type`: `fswatch`
- `path`: Directory to watch (relative to PROJECT_ROOT or absolute)
- `events`: fswatch events to monitor
- `exclude`: Patterns to exclude from watching
- `debounce`: Seconds to wait after last change before triggering (default: 15)
- `rules`: List of matching rules

**Rule fields:**
- `match`: Regex pattern for relative path
- `exclude`: (optional) Regex pattern to exclude
- `condition`: (optional) Shell command that must succeed
- `action`: Script to run (relative to PROJECT_ROOT or absolute)

### cron (Time-Based)

```yaml
name: heartbeat
type: cron
schedule: "*/30 * * * *"
action: skills/my-skill/scripts/heartbeat.sh
```

**Fields:**
- `name`: Unique identifier
- `type`: `cron`
- `schedule`: Cron expression
- `action`: Script to run

## Commands

```bash
# List all discovered watchers
skills/watcher/run.sh list

# Show status (running/stopped)
skills/watcher/run.sh status

# Start all watchers
skills/watcher/run.sh start

# Start specific watcher
skills/watcher/run.sh start vault-files

# Stop all watchers
skills/watcher/run.sh stop

# Stop specific watcher
skills/watcher/run.sh stop vault-files

# Tail logs for a watcher
skills/watcher/run.sh logs vault-files
```

## Event Types (fswatch)

Common fswatch events:
- `Created` - File created
- `Updated` - File modified
- `Removed` - File deleted
- `Renamed` - File renamed
- `AttributeModified` - Permissions or metadata changed
- `MovedFrom` - File moved from watched directory
- `MovedTo` - File moved to watched directory

## Example: Vault File Watcher

```yaml
# skills/agent/vault/watch/files.yaml
name: vault-files
type: fswatch
path: vault/
events: [Created, Updated, AttributeModified, Renamed]
exclude:
  - "\.DS_Store"
  - "\.obsidian"
  - "/files/"
debounce: 15

rules:
  # New note in vault root
  - match: "^[^/]+\\.md$"
    exclude: "^index\\.md$"
    action: skills/vault/scripts/new-note.sh

  # Submit task when flagged
  - match: "^tasks/.*\\.md$"
    condition: "grep -q '^submit: true'"
    action: skills/vault/scripts/submit.sh
```

## Other Watcher Types

For watchers not covered by fswatch/cron:

### Hammerspoon (macOS System Events)

```lua
-- ~/.hammerspoon/init.lua
hs.application.watcher.new(function(name, event, app)
  if event == hs.application.watcher.launched then
    os.execute('claude -p "App launched: '..name..'"')
  end
end):start()
```

### urlwatch (API Polling)

For APIs without webhooks:
```bash
pip install urlwatch
urlwatch --add "https://example.com/status"
```

---

**Note:** fswatch is required for file watchers. Install with `brew install fswatch` (macOS) or `apt install inotify-tools` (Linux).
