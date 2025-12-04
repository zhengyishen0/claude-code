# Claude Code Project

## Tool Design Principles

When creating tools/skills:
1. **Self-documenting** - Tools document themselves via `help` command
2. **Help as default** - Running with no args shows help + prereq check
3. **No separate doc files** - Brief description in CLAUDE.md, full docs in tool's help
4. **Prereq check on first use** - Tools check/install dependencies when run without args

## Available Skills

### 1. chrome-cli-plus
Browser automation for Google Chrome. Located at `skills/chrome-cli/`.

Run `skills/chrome-cli/chrome-cli-plus.sh` for usage, examples, and setup.

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
