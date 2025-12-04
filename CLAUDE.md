# Claude Code Project

## Available Skills

### 1. chrome-cli-plus
Browser automation tool for controlling Google Chrome. Located at `skills/chrome-cli/`.

**Usage:** `skills/chrome-cli/chrome-cli-plus.sh <command> [args]`

**Commands:**
- `recon` / `r` - Get page structure in markdown format
- `open` / `o` - Open URL and get page structure
- `click` / `c` - Smart click using `[text@aria](#testid)` format
- `input` / `i` - Set input values
- `wait` / `w` - Wait for page load
- `tabs` / `t` - List browser tabs
- `info` - Current tab info
- `close` - Close tab

**Click Examples:**
```bash
# Copy selector directly from recon output
skills/chrome-cli/chrome-cli-plus.sh click "[@Search](#search-btn)"
skills/chrome-cli/chrome-cli-plus.sh click "[Filters](#filter-btn)"
skills/chrome-cli/chrome-cli-plus.sh click "button.submit"  # CSS fallback
```

**Input Examples:**
```bash
skills/chrome-cli/chrome-cli-plus.sh input "#email" "test@example.com"
skills/chrome-cli/chrome-cli-plus.sh input --aria "Where" "New York"
```

Run `skills/chrome-cli/chrome-cli-plus.sh help` for full documentation.

---

### 2. cli-tools
Modern CLI tool replacements for traditional Unix commands. Located at `skills/cli-tools/`.

**Quick Reference:**
- `rg` instead of `grep` - Faster text search
- `fd` instead of `find` - Faster file search
- `eza` instead of `ls` - Color-coded with git status
- `bat` instead of `cat` - Syntax highlighting
- `dust` instead of `du` - Visual disk usage
- `xh` instead of `curl` - Human-friendly HTTP

See `skills/cli-tools/SKILL.md` for full documentation.
