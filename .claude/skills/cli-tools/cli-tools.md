# Modern CLI Tool Replacements

> Reference guide for modern CLI tools used in zenix. See `system-overview.md` for how these integrate into the architecture.

A reference list of modern CLI tools that are faster and more feature-rich than traditional Unix commands.

## File Navigation & Management

| Traditional | Modern Alternative    | Why Better                                  |
| ----------- | --------------------- | ------------------------------------------- |
| `cd`        | `z` (zoxide)          | Fuzzy directory jumping based on frequency  |
| `ls`        | `eza` (exa successor) | Color-coded, git status, tree view          |
| `find`      | `fd`                  | Faster, simpler syntax, respects .gitignore |
| `du`        | `dust`                | Visual disk usage with colors               |
| `tree`      | `broot`               | Interactive tree navigation                 |

## Text Processing & Search

| Traditional | Modern Alternative | Why Better                                   |
| ----------- | ------------------ | -------------------------------------------- |
| `grep`      | `ripgrep` (rg)     | Faster, respects .gitignore, better defaults |
| `sed`       | `sd`               | Simpler syntax, safer defaults               |
| `awk`       | `miller` (mlr)     | Better for CSV/JSON processing               |
| `cut`       | `choose`           | More intuitive field selection               |
| `sort`      | `huniq`            | Better duplicate handling                    |

## System Monitoring & Process Management

| Traditional | Modern Alternative   | Why Better                         |
| ----------- | -------------------- | ---------------------------------- |
| `ps`        | `procs`              | Colored output, better formatting  |
| `top`       | `btop` / `htop`      | Interactive, visual, more info     |
| `df`        | `duf`                | Better formatting, colored output  |
| `free`      | Built into btop/htop | More visual memory info            |
| `netstat`   | `ss`                 | Faster, more detailed network info |

## File Content & Viewing

| Traditional | Modern Alternative      | Why Better                           |
| ----------- | ----------------------- | ------------------------------------ |
| `cat`       | `bat`                   | Syntax highlighting, git integration |
| `less`      | `bat --paging=always`   | Syntax highlighting in pager         |
| `tail -f`   | `multitail`             | Multiple files, better colors        |
| `head`      | `bat --line-range=1:10` | With syntax highlighting             |

## JSON/Data Processing

| Traditional    | Modern Alternative       | Why Better                                |
| -------------- | ------------------------ | ----------------------------------------- |
| `jq`           | `jq` (still best)        | But also `fx` for interactive browsing    |
| `curl`         | `httpie` (`http`) / `xh` | Human-friendly HTTP client (xh is faster) |
| `wget`         | `wget2` or `aria2c`      | Parallel downloads, better resuming       |
| CSV processing | `xsv`                    | Fast CSV slicing, stats, indexing         |
| YAML           | `yq`                     | Like jq but for YAML                      |

## Git Operations

| Traditional  | Modern Alternative          | Why Better                      |
| ------------ | --------------------------- | ------------------------------- |
| `git status` | `git status -sb`            | Shorter, branch info            |
| `git log`    | `git log --oneline --graph` | Visual branch history           |
| `git diff`   | `delta`                     | Better diff highlighting        |
| `git blame`  | `git blame -w -C`           | Ignore whitespace, detect moves |

## Archive & Compression

| Traditional | Modern Alternative                      | Why Better                       |
| ----------- | --------------------------------------- | -------------------------------- |
| `tar`       | `tar` (but with `--verbose --progress`) | Better feedback                  |
| `zip/unzip` | `7z`                                    | Better compression, more formats |
| `gzip`      | `zstd`                                  | Faster compression/decompression |

## File Watching & Monitoring

| Traditional   | Modern Alternative | Why Better                                              |
| ------------- | ------------------ | ------------------------------------------------------- |
| `watch`       | `entr`             | More intelligent file watching, runs commands on change |
| `tail -f`     | `lnav`             | Log navigator with filtering and analysis               |
| `inotifywait` | `watchexec`        | Cross-platform, pattern-based file watching             |
| `crontab`     | `just`             | Modern task runner with better syntax                   |

## Browser & Screenshot Automation

| Purpose             | Tool                | Why Useful                                           |
| ------------------- | ------------------- | ---------------------------------------------------- |
| Chrome automation   | `chrome-cli`        | Control Chrome from terminal: tabs, URLs, navigation |
| Screenshot capture  | `screenshot` (macOS)| Native macOS screenshot with formats and clipboard   |
| Headless screenshot | `pageres-cli`       | Capture web pages at various resolutions             |
| Screen recording    | `terminalizer`      | Record and share terminal sessions                   |

### chrome-cli Usage

Control Google Chrome from the command line (macOS):

```bash
# Install
brew install chrome-cli

# Common commands
chrome-cli list tabs              # List all open tabs
chrome-cli list windows           # List all windows
chrome-cli open https://example.com  # Open URL in new tab
chrome-cli info                   # Get current tab info
chrome-cli source                 # Get HTML source of current tab
chrome-cli execute '(function() { return document.title; })()'  # Execute JS

# Useful for agents - get page content for analysis
chrome-cli source | bat --language=html
```

### screenshot (macOS) Usage

Built-in macOS screenshot utility:

```bash
# Capture entire screen to file
screencapture screen.png

# Capture specific window (interactive)
screencapture -W window.png

# Capture selection (interactive)
screencapture -s selection.png

# Capture to clipboard instead of file
screencapture -c

# Capture with delay (5 seconds)
screencapture -T 5 delayed.png

# Capture specific display (for multi-monitor)
screencapture -D 1 display1.png

# Common formats: png (default), jpg, pdf, gif
screencapture -t jpg screen.jpg
```

## Installation Commands for zenix

```bash
# Package manager installations (choose based on OS)

# macOS (Homebrew)
brew install zoxide eza fd dust ripgrep sd procs btop duf bat httpie delta zstd xh xsv yq entr lnav watchexec just chrome-cli
# Note: screencapture is built-in to macOS, no installation needed

# Linux (apt/ubuntu)
sudo apt install zoxide exa fd-find dust ripgrep sd-replace procs btop duf bat httpie git-delta zstd
# Additional via cargo/npm:
cargo install xh xsv watchexec
npm install -g yq

# Linux (cargo - if available)
cargo install zoxide eza fd-find dust ripgrep sd procs btop duf bat xh xsv watchexec

# Arch Linux
sudo pacman -S zoxide eza fd dust ripgrep sd procs btop duf bat httpie git-delta zstd
yay -S xh xsv yq entr lnav watchexec just
```

## Nu Shell Integration

Nu Shell has some built-in modern equivalents:

| Function | Nu Shell Native                 | External Tool             |
| -------- | ------------------------------- | ------------------------- |
| ls       | `ls` (built-in, already modern) | `eza` for extra features  |
| grep     | `grep` (built-in)               | `rg` for speed            |
| find     | `glob` (built-in)               | `fd` for complex searches |
| ps       | `ps` (built-in, structured)     | `procs` for colors        |
| du       | `du` (built-in)                 | `dust` for visualization  |

## zenix-Specific Usage

For zenix trigger system and memory management:

```nu
# File watching with modern tools - using entr
def watch-sessions [] {
  fd -e jsonl . ~/.claude/projects
  | each { |file| echo $file }
  | save /tmp/watch-list.txt
  entr -p nu -c 'index-session-changes' < /tmp/watch-list.txt
}

# Memory search with ripgrep and xsv for CSV-like index
def recall [query: string] {
  rg $query ~/.zenix/index.txt
  | lines
  | each { |line|
      # Use xsv if index is CSV format
      let parts = ($line | split column "|")
      let cell_id = $parts.0
      let file_path = $parts.1

      # Use bat to show content with syntax highlighting
      bat --line-range 1:5 $file_path
  }
}

# System monitoring for running agents
def list-agents [] {
  procs | where name =~ "claude|tmux" | sort-by cpu
}

# Log monitoring with lnav
def watch-agent-logs [] {
  lnav ~/.zenix/logs/*.log
}

# Task automation with just
def run-memory-tasks [] {
  just index-all-sessions
  just cleanup-old-ratings
  just backup-memory
}

# Disk usage for memory cells
def memory-usage [] {
  dust ~/.zenix ~/.claude/projects
}
```

## Performance Comparison Examples

```bash
# Traditional vs Modern - Search
time grep -r "pattern" /large/directory          # ~2.5s
time rg "pattern" /large/directory               # ~0.3s

# Traditional vs Modern - Directory listing
time ls -la /usr/bin | wc -l                     # ~0.1s
time eza -la /usr/bin | wc -l                    # ~0.05s (with colors!)

# Traditional vs Modern - File finding
time find /usr -name "*.json" 2>/dev/null        # ~3s
time fd "\.json$" /usr                           # ~0.5s

# Traditional vs Modern - Directory jumping
cd /very/long/path/that/i/use/frequently         # Type full path
z freq                                           # Fuzzy match to frequently used
```

## Aliases for Transition

```bash
# Add to ~/.bashrc or ~/.zshrc for gradual transition
alias ll='eza -la --git'
alias la='eza -la'
alias l='eza -l'
alias find='fd'
alias grep='rg'
alias cat='bat'
alias cd='z'
alias ps='procs'
alias du='dust'
alias df='duf'
alias top='btop'
```

## Why This Matters for zenix

1. **Speed**: Modern tools are often 2-10x faster
2. **Better defaults**: Safer, more intuitive behavior
3. **Structured output**: Many work better with Nu shell's data processing
4. **Git awareness**: Respect .gitignore, show git status
5. **Colors & formatting**: Better for debugging and monitoring
6. **Future-proof**: Active development vs legacy maintenance

Use these modern alternatives in zenix trigger scripts and memory system for better performance and developer experience.

## Justfile Example for zenix

Create a `justfile` for common zenix tasks:

```just
# zenix task automation
set shell := ["nu", "-c"]

# Initialize memory system
init:
    mkdir ~/.zenix/racu
    touch ~/.zenix/index.txt

# Index all existing Claude sessions
index-all:
    fd -e jsonl . ~/.claude/projects | each { |file| index-session $file }

# Search memory with modern tools
search query:
    rg {{query}} ~/.zenix/index.txt | head -10

# Monitor system health
health:
    procs | where name =~ "claude|tmux"
    dust ~/.zenix
    duf | where filesystem =~ "/"

# Start file watching daemon
watch:
    tmux new-session -d -s memory-watcher "entr -r nu -c 'index-session-changes' <<< $(fd -e jsonl ~/.claude/projects)"

# Backup memory system
backup:
    tar -czf ~/.zenix/backup-$(date +%Y%m%d).tar.gz ~/.zenix/racu ~/.zenix/index.txt

# Clean old ratings (older than 30 days)
cleanup:
    fd -t f --changed-before 30d . ~/.zenix/racu | each { |file| rm $file }
```
