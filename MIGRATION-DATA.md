# Data & Structure Migration Plan

Restructure the project as `~/.claude-code` with centralized data management.

## Overview

```
Before:
~/.claude/                    # Claude's default location
├── skills/
│   ├── browser/
│   │   └── data/            # Mixed with code
│   └── memory/
│       └── data/            # Mixed with code
├── projects/                 # Auto-memory per project
└── settings.json

/Users/zhengyishen/Codes/claude-code/
├── .claude/
│   └── skills -> ~/.claude/skills  # Symlink
└── ...

After:
~/.claude-code/               # Single source of truth
├── skills/                   # Code only (submodules)
├── data/                     # All runtime data (gitignored)
│   ├── browser/
│   ├── memory/
│   ├── google/
│   └── feishu/
├── hooks/
├── memory/                   # Auto-memory
├── vault/
└── settings.json

~/.claude -> ~/.claude-code   # Symlink for Claude compatibility
```

## Why This Structure

1. **Separation of concerns** - Code vs data clearly separated
2. **Single location** - Everything under `~/.claude-code`
3. **Git-friendly** - `data/` gitignored, skills as submodules
4. **Portable paths** - All skills use `~/.claude-code/data/SKILL/`

## Data Inventory

### Data to Move

| Source | Destination | Size |
|--------|-------------|------|
| `~/.claude/skills/browser/data/` | `data/browser/chrome/` | ~500MB |
| `~/.claude/skills/browser/profiles/` | `data/browser/profiles/` | ~200MB |
| `~/.claude/skills/memory/data/` | `data/memory/` | ~270MB |
| `~/.config/api/google/` | `data/google/` | <1KB |
| `~/.config/api/feishu/` | `data/feishu/` | <1KB |

### Sensitive Files

| File | Contains | Action |
|------|----------|--------|
| `data/google/token.json` | OAuth tokens | Keep in data/, gitignore |
| `data/google/client_secret.json` | OAuth client | Keep in data/, gitignore |
| `data/feishu/credentials.json` | App ID/secret | Keep in data/, gitignore |
| `data/browser/chrome/` | Cookies, history | Keep in data/, gitignore |

## Step 1: Create New Structure

```bash
cd /Users/zhengyishen/Codes/claude-code

# Create data directory structure
mkdir -p data/{browser,memory,google,feishu}

# Create/update .gitignore
cat >> .gitignore << 'EOF'

# Runtime data
data/

# But keep the structure
!data/.gitkeep
EOF

# Add .gitkeep to preserve structure
touch data/.gitkeep
```

## Step 2: Move Skills to Project Root

```bash
# Move skills from .claude/ to project root
mv .claude/skills ./skills

# Or copy from global location
cp -r ~/.claude/skills ./skills
```

## Step 3: Move Runtime Data

```bash
# Browser data
mv ~/.claude/skills/browser/data ./data/browser/chrome
mv ~/.claude/skills/browser/profiles ./data/browser/profiles

# Memory data
mv ~/.claude/skills/memory/data/* ./data/memory/

# Google credentials
mv ~/.config/api/google/* ./data/google/

# Feishu credentials
mv ~/.config/api/feishu/* ./data/feishu/
```

## Step 4: Update Skills to Use New Paths

Each skill needs to look for data in `~/.claude-code/data/SKILL/`.

### browser/SKILL.md or browser/*.py

```python
# Before
DATA_DIR = Path(__file__).parent / 'data'

# After
DATA_DIR = Path.home() / '.claude-code' / 'data' / 'browser'
```

### memory/SKILL.md or memory/*.sh

```bash
# Before
DATA_DIR="$(dirname "$0")/data"

# After
DATA_DIR="$HOME/.claude-code/data/memory"
```

### google/auth.py

```python
# Before
CONFIG_DIR = Path.home() / '.config' / 'api' / 'google'

# After
CONFIG_DIR = Path.home() / '.claude-code' / 'data' / 'google'
```

### feishu/auth.py

```python
# Before
CONFIG_DIR = Path.home() / '.config' / 'api' / 'feishu'

# After
CONFIG_DIR = Path.home() / '.claude-code' / 'data' / 'feishu'
```

## Step 5: Set Up Symlink

```bash
# Backup existing ~/.claude if needed
mv ~/.claude ~/.claude.bak

# Create symlink
ln -s /Users/zhengyishen/Codes/claude-code ~/.claude-code

# Also link as ~/.claude for Claude compatibility
ln -s ~/.claude-code ~/.claude
```

## Step 6: Update Project References

### CLAUDE.md

```markdown
## Environment

Project root: `~/.claude-code/`
Skills: `~/.claude-code/skills/`
Data: `~/.claude-code/data/`
```

### hooks/

Update any hooks that reference old paths.

## Final Structure

```
~/.claude-code/
├── skills/                    # Git submodules
│   ├── browser/
│   ├── memory/
│   ├── google/
│   ├── feishu/
│   └── ...
├── data/                      # Gitignored
│   ├── browser/
│   │   ├── chrome/            # Chrome profile data
│   │   └── profiles/          # Named profiles
│   ├── memory/
│   │   ├── memory-index.tsv
│   │   └── memory-index-nlp.tsv
│   ├── google/
│   │   ├── token.json
│   │   └── client_secret.json
│   └── feishu/
│       └── credentials.json
├── hooks/
├── memory/                    # Auto-memory (MEMORY.md)
├── vault/
├── CLAUDE.md
├── .gitignore
└── settings.json

~/.claude -> ~/.claude-code    # Symlink
```

## Verification Checklist

- [ ] `data/` folder created with correct structure
- [ ] All runtime data moved from skills to data/
- [ ] Skills updated to use new data paths
- [ ] Symlink `~/.claude` -> `~/.claude-code` works
- [ ] `data/` is gitignored
- [ ] Skills still function correctly:
  - [ ] `/browser` can launch Chrome
  - [ ] `/memory` can search sessions
  - [ ] `/google` can authenticate
  - [ ] `/feishu` can authenticate
- [ ] No secrets in git history

## Rollback Plan

```bash
# Restore original structure
rm ~/.claude ~/.claude-code
mv ~/.claude.bak ~/.claude

# Restore data to original locations
mv data/browser/chrome ~/.claude/skills/browser/data
mv data/browser/profiles ~/.claude/skills/browser/profiles
mv data/memory/* ~/.claude/skills/memory/data/
mv data/google/* ~/.config/api/google/
mv data/feishu/* ~/.config/api/feishu/
```

## Notes

- Complete this migration BEFORE the submodule migration
- Test each skill after updating paths
- Consider rotating Google/Feishu credentials after migration
