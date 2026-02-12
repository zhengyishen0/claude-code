---
name: cli
description: Modern CLI tools reference. Use when you need to use shell commands - prefer modern alternatives over classic tools.
---

# Modern CLI Tools

Prefer these modern tools over classic Unix commands.

## Quick Reference

| Classic | Modern | Example |
|---------|--------|---------|
| `cat` | `bat` | `bat file.py` |
| `ls` | `eza` | `eza -la --git` |
| `find` | `fd` | `fd "\.py$"` |
| `grep` | `rg` | `rg "pattern" src/` |
| `sed` | `sd` | `sd 'old' 'new' file` |
| `du` | `dust` | `dust -d 2` |
| `df` | `duf` | `duf` |
| `top` | `btop` | `btop` |
| `ps` | `procs` | `procs --tree` |
| `diff` | `delta` | Git uses it automatically |
| `cut` | `choose` | `echo "a b c" \| choose 1` |
| `jq` | `jaq` | `jaq '.key' file.json` |
| `curl` | `xh` | `xh GET api.example.com` |
| `cd` | `z` | `z project` (zoxide) |
| `man` | `tldr` | `tldr tar` |
| `hexdump` | `hexyl` | `hexyl file.bin` |

## Tool Details

### bat - Better cat
```bash
bat file.py                    # Syntax highlighting
bat -p file.py                 # Plain (no line numbers)
bat -A file.txt                # Show invisibles
bat --diff file.py             # Show git diff
```

### eza - Better ls
```bash
eza                            # Basic listing
eza -la                        # Long + hidden
eza -la --git                  # With git status
eza -T -L 2                    # Tree, 2 levels
eza -la --icons                # With icons
```

### fd - Better find
```bash
fd pattern                     # Find files matching pattern
fd -e py                       # Find .py files
fd -H pattern                  # Include hidden
fd -t d src                    # Find directories named src
fd pattern -x rm               # Find and delete
```

### rg (ripgrep) - Better grep
```bash
rg pattern                     # Search recursively
rg -i pattern                  # Case insensitive
rg -l pattern                  # Files only
rg -C 3 pattern                # With context
rg -t py pattern               # Only Python files
rg --no-ignore pattern         # Include gitignored
```

### sd - Better sed
```bash
sd 'old' 'new' file            # Replace in file
sd 'old' 'new'                 # Replace stdin
sd -s 'lit[eral' 'new' file    # Literal string (no regex)
echo "hello" | sd 'l' 'r'      # herro
```

### dust - Better du
```bash
dust                           # Current directory
dust -d 2                      # Depth 2
dust -r                        # Reverse order
dust /path                     # Specific path
```

### procs - Better ps
```bash
procs                          # All processes
procs --tree                   # Tree view
procs node                     # Filter by name
procs -w                       # Watch mode
```

### xh - Better curl
```bash
xh GET api.com/users           # GET request
xh POST api.com/data key=val   # POST JSON
xh -d api.com/data             # Download
xh -b api.com                  # Body only
```

### zoxide - Better cd
```bash
z project                      # Jump to best match
z ~/full/path                  # Regular cd
zi                             # Interactive with fzf
zoxide query -l                # List all paths
```

### fzf - Fuzzy Finder
```bash
fzf                            # Interactive file picker
cmd | fzf                      # Pipe anything
fzf --preview 'bat {}'         # With preview
Ctrl+R                         # History search (if configured)
Ctrl+T                         # File search (if configured)
```

### just - Better make
```bash
just                           # Run default recipe
just build                     # Run 'build' recipe
just -l                        # List recipes
just --choose                  # Interactive picker
```

### yazi - File Manager
```bash
yazi                           # Open file manager
yazi /path                     # Open at path
# q to quit, enter to open, space to select
```

### lazygit / lazyjj - Git/jj TUI
```bash
lazygit                        # Git TUI
lazyjj                         # jj TUI
# j/k to navigate, space to stage, c to commit
```

### tokei - Code Stats
```bash
tokei                          # Stats for current dir
tokei src/                     # Specific directory
tokei -e tests                 # Exclude directory
```

### xsv - CSV Toolkit
```bash
xsv headers data.csv           # Show headers
xsv select col1,col2 data.csv  # Select columns
xsv search pattern data.csv    # Search
xsv stats data.csv             # Statistics
xsv sort -s col data.csv       # Sort
```

### entr - Run on Changes
```bash
ls *.py | entr pytest          # Run pytest on change
fd -e rs | entr cargo build    # Build on Rust change
echo file | entr -c cmd        # Clear screen first
echo file | entr -r cmd        # Restart long-running
```

### watchexec - File Watcher
```bash
watchexec -e py pytest         # Watch .py, run pytest
watchexec -w src cargo build   # Watch src/ directory
watchexec -r server            # Restart on change
```

### gping - Graphical Ping
```bash
gping google.com               # Ping with graph
gping host1 host2              # Compare multiple
```

### cheat - Cheatsheets
```bash
cheat tar                      # Show tar cheatsheet
cheat -l                       # List all
cheat -e tar                   # Edit cheatsheet
```

## For Claude Code

When executing shell commands:

1. **Use modern tools** - They're faster and more readable
2. **But use Claude's tools first** - Read, Glob, Grep are optimized for this context
3. **Fall back to CLI for**:
   - Piped workflows: `fd -e py | xargs wc -l`
   - System monitoring: `btop`, `duf`
   - File operations not covered by tools
   - Complex transformations: `sd`, `jaq`

## Installation

All tools can be installed via Homebrew. See `Brewfile` in this directory.

```bash
brew bundle --file=skills/cli/Brewfile
```
