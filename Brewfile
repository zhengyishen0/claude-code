# Brewfile - Claude Code Prerequisites
# Install all: brew bundle install
# Check status: brew bundle check
# Update & lock: brew bundle install && git add Brewfile.lock.json

# Custom taps
tap "anthropics/claude"

# ============================================================================
# Required Tools
# ============================================================================

# System tools
brew "git"               # Version control (usually pre-installed on macOS)

# Runtime with version constraint
brew "node@18"           # Node.js 18.x for tool scripts (CDP browser automation)

# Claude CLI (cask, not formula)
cask "claude-code"       # Claude Code CLI tool

# ============================================================================
# Highly Recommended Tools
# Uncomment this entire section for a modern developer experience
# ============================================================================

# Essential Utilities
# brew "stow"            # Dotfile management via symlinks - HIGHLY recommended
# brew "tmux"            # Terminal multiplexer - essential for remote work
# brew "direnv"          # Auto-load env vars per directory - game changer
# brew "tree"            # Display directory structure as tree
# brew "wget"            # Download tool (complement to curl)
# brew "tldr"            # Simplified, practical man pages
# brew "htop"            # Interactive process viewer (more common than btop)

# Shell & Prompt
# brew "starship"        # Cross-shell prompt - beautiful & fast
# brew "zsh-autosuggestions"  # Fish-like suggestions for zsh
# brew "zsh-syntax-highlighting"  # Syntax highlighting for zsh

# ============================================================================
# Optional Modern CLI Tools
# Uncomment to install improved alternatives to Unix commands
# ============================================================================

# File Navigation & Search
# brew "ripgrep"         # Fast grep (rg) - 10-100x faster, respects .gitignore
# brew "fd"              # Fast find - simpler syntax, respects .gitignore
# brew "fzf"             # Fuzzy finder - interactive search EVERYWHERE
# brew "eza"             # Modern ls with git integration & colors
# brew "zoxide"          # Smart cd that learns (z command) - huge productivity boost
# brew "broot"           # Modern file tree navigation & search

# Text Processing & Viewing
# brew "bat"             # Cat with syntax highlighting & git integration
# brew "jq"              # JSON processor - essential for API work
# brew "yq"              # YAML/XML processor (like jq for YAML)
# brew "sd"              # Modern sed - simpler regex syntax
# brew "difftastic"      # Structural diff - understands syntax

# System Monitoring & Info
# brew "btop"            # Modern top/htop - best UI
# brew "procs"           # Modern ps - better output & filtering
# brew "duf"             # Modern df - colorful disk usage
# brew "dust"            # Modern du - visual directory sizes
# brew "ncdu"            # NCurses disk usage - interactive analyzer
# brew "bandwhich"       # Network bandwidth monitor per process

# File Management
# brew "trash"           # Safe rm - moves to trash instead of deleting
# brew "rename"          # Rename multiple files with regex

# Network & HTTP
# brew "httpie"          # User-friendly curl alternative (http command)
# brew "xh"              # Fast httpie alternative in Rust
# brew "curlie"          # Curl with httpie syntax

# Archive & Compression
# brew "zstd"            # Fast compression - better than gzip
# brew "p7zip"           # 7-Zip for Unix
# brew "unrar"           # Extract RAR archives

# Development Tools
# brew "gh"              # GitHub CLI - manage PRs/issues from terminal
# brew "delta"           # Better git diff with syntax highlighting
# brew "lazygit"         # Terminal UI for git - amazing for complex operations
# brew "watchexec"       # File watcher - run commands on changes
# brew "entr"            # Run commands when files change (alternative to watchexec)
# brew "just"            # Command runner - better than make
# brew "tokei"           # Count lines of code - fast & accurate
# brew "hyperfine"       # Command benchmarking tool
