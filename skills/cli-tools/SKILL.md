---
name: cli-tools
description: Modern CLI tool replacements for traditional Unix commands like grep, find, ls, cat, du, ps, and curl. Use when user mentions searching files (ripgrep/rg), finding files (fd), listing directories (eza), viewing files (bat), disk usage (dust), process monitoring (procs/btop), HTTP requests (xh), or JSON/CSV processing (jq/xsv). Provides faster, safer alternatives with better defaults and syntax highlighting.
---

# Modern CLI Tools Skill

Use modern CLI tool replacements instead of traditional Unix commands for better performance, safety, and developer experience.

## Quick Reference

### File Navigation & Management
- `z` (zoxide) instead of `cd` - Fuzzy directory jumping
- `eza` instead of `ls` - Color-coded, git status, tree view
- `fd` instead of `find` - Faster, simpler syntax, respects .gitignore
- `dust` instead of `du` - Visual disk usage
- `broot` instead of `tree` - Interactive tree navigation

### Text Processing & Search
- `rg` (ripgrep) instead of `grep` - Faster, better defaults
- `sd` instead of `sed` - Simpler syntax, safer
- `mlr` (miller) instead of `awk` - Better for CSV/JSON
- `choose` instead of `cut` - More intuitive field selection

### System Monitoring
- `procs` instead of `ps` - Colored output, better formatting
- `btop`/`htop` instead of `top` - Interactive, visual
- `duf` instead of `df` - Better formatting, colored output

### File Content & Viewing
- `bat` instead of `cat` - Syntax highlighting, git integration
- `bat --paging=always` instead of `less` - Syntax highlighting in pager

### JSON/Data Processing
- `jq` - Still best for JSON processing
- `fx` - Interactive JSON browsing
- `xh` instead of `curl` - Human-friendly HTTP client (faster than httpie)
- `xsv` - Fast CSV slicing, stats, indexing
- `yq` - Like jq but for YAML

### Browser & Screenshot Automation (macOS)
- `chrome-cli` - Control Chrome from terminal
- `screencapture` - Native macOS screenshot utility

### File Watching & Monitoring
- `entr` instead of `watch` - Intelligent file watching
- `lnav` instead of `tail -f` - Log navigator with filtering
- `watchexec` instead of `inotifywait` - Cross-platform file watching
- `just` instead of `crontab` - Modern task runner

## Installation

```bash
# macOS (Homebrew)
brew install zoxide eza fd dust ripgrep sd procs btop duf bat httpie delta zstd xh xsv yq entr lnav watchexec just chrome-cli

# Linux (apt/ubuntu)
sudo apt install zoxide exa fd-find dust ripgrep sd-replace procs btop duf bat httpie git-delta zstd

# Linux (cargo)
cargo install zoxide eza fd-find dust ripgrep sd procs btop duf bat xh xsv watchexec

# Arch Linux
sudo pacman -S zoxide eza fd dust ripgrep sd procs btop duf bat httpie git-delta zstd
yay -S xh xsv yq entr lnav watchexec just
```

## Common Usage Patterns

### File Search
```bash
# Traditional
find /path -name "*.json" -type f

# Modern
fd "\.json$" /path
fd -e json  # Even simpler
```

### Text Search
```bash
# Traditional
grep -r "pattern" /path

# Modern
rg "pattern" /path  # Faster, respects .gitignore
```

### Directory Listing
```bash
# Traditional
ls -la

# Modern
eza -la --git  # With git status
eza -la --tree --level=2  # Tree view
```

### File Content
```bash
# Traditional
cat file.js

# Modern
bat file.js  # Syntax highlighting
```

### Disk Usage
```bash
# Traditional
du -sh *

# Modern
dust  # Visual, colored output
```

### HTTP Requests
```bash
# Traditional
curl -X POST -H "Content-Type: application/json" -d '{"key":"value"}' https://api.example.com

# Modern
xh POST https://api.example.com key=value
```

### Chrome Automation (macOS)
```bash
chrome-cli list tabs              # List all open tabs
chrome-cli open https://example.com  # Open URL
chrome-cli execute 'document.title'  # Execute JavaScript
chrome-cli source                 # Get HTML source
```

### Screenshots (macOS)
```bash
screencapture screen.png          # Entire screen
screencapture -W window.png       # Specific window
screencapture -s selection.png    # Selection
screencapture -c                  # To clipboard
screencapture -T 5 delayed.png    # 5 second delay
```

### File Watching
```bash
# Traditional
while true; do command; sleep 2; done

# Modern
watchexec -w src/ npm test  # Run tests when src/ changes
fd -e md | entr -s 'pandoc $0 -o output.pdf'  # Convert markdown on change
```

## Performance Benefits

- **ripgrep**: 2-10x faster than grep
- **fd**: 2-5x faster than find
- **eza**: Similar speed to ls but with more features
- **bat**: Comparable to cat with syntax highlighting
- **dust**: Faster than du with visual output

## Why Use These Tools

1. **Speed**: Modern tools are significantly faster
2. **Better defaults**: Safer, more intuitive behavior
3. **Git awareness**: Respect .gitignore, show git status
4. **Colors & formatting**: Better for debugging and monitoring
5. **Simpler syntax**: More user-friendly than traditional tools
6. **Active development**: Regular updates vs legacy maintenance

## Integration Tips

### Aliases for Gradual Transition
```bash
alias ll='eza -la --git'
alias la='eza -la'
alias find='fd'
alias grep='rg'
alias cat='bat'
alias ps='procs'
alias du='dust'
alias df='duf'
alias top='btop'
```

### Task Automation with just
Create a `justfile` in your project:
```just
# Set shell to use
set shell := ["bash", "-c"]

# Build project
build:
    cargo build --release

# Run tests
test:
    cargo test

# Watch and rebuild
watch:
    watchexec -w src/ just build

# Search codebase
search query:
    rg {{query}} src/
```

For complete reference and examples, see [cli-tools.md](cli-tools.md).
