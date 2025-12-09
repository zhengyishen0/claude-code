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
brew "chrome-cli"        # Chrome browser automation via CLI

# Runtime with version constraint
brew "node@18"           # Node.js 18.x for tool scripts (playwright, etc)

# Claude CLI (cask, not formula)
cask "claude-code"       # Claude Code CLI tool

# ============================================================================
# Optional Modern CLI Tools
# Uncomment to install improved alternatives to Unix commands
# ============================================================================

# File Navigation & Search
# brew "ripgrep"         # Fast grep alternative (rg) - 10-100x faster than grep
# brew "fd"              # Fast find alternative - simpler syntax, respects .gitignore
# brew "fzf"             # Fuzzy finder - interactive file/command search
# brew "eza"             # Modern ls alternative with Git integration
# brew "zoxide"          # Smart cd that learns your habits (z command)
# brew "broot"           # Modern file tree navigation

# Text Processing
# brew "bat"             # Cat with syntax highlighting and Git integration
# brew "jq"              # JSON processor and pretty printer
# brew "yq"              # YAML/XML processor (like jq for YAML)
# brew "sd"              # Modern sed alternative - simpler regex syntax

# System Monitoring
# brew "btop"            # Modern top/htop alternative with better UI
# brew "procs"           # Modern ps alternative
# brew "duf"             # Modern df alternative - disk usage viewer
# brew "dust"            # Modern du alternative - directory size analyzer

# File Management
# brew "trash"           # Safe rm - moves to trash instead of deleting

# Archive Tools
# brew "zstd"            # Fast compression algorithm
# brew "7zip"            # Universal archive tool

# Development
# brew "gh"              # GitHub CLI - manage PRs, issues from terminal
# brew "delta"           # Better git diff with syntax highlighting
# brew "watchexec"       # File watcher - run commands on file changes
# brew "just"            # Command runner (like make but better)
