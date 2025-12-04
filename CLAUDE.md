# Claude Code Project

## Tool Design Principles

When creating tools:
1. **Self-documenting** - Tools document themselves via `help` command
2. **Help as default** - Running with no args shows help + prereq check
3. **No separate doc files** - Brief description in CLAUDE.md, full docs in tool's help
4. **Prereq check on first use** - Tools check/install dependencies when run without args
5. **Standard entry point** - Each tool uses `run.sh`, name derived from folder

## Available Tools

<!-- TOOLS:AUTO-GENERATED -->

Universal entry: `tools/run.sh <tool> [command] [args...]`

### chrome
Browser automation with React/SPA support

Run `tools/chrome/run.sh` for full help.

**Commands:** recon, open, wait, click, input, esc, tabs, info, close, help

**Key Principles:**
1. Recon first - understand page before interacting
2. Wait after actions - use wait after clicks/navigation
3. Re-run recon - verify state changes after actions
4. URL params > clicking - faster and more reliable
5. Keep window clean - close unused tabs before opening
6. JS returns strings - chrome-cli crashes otherwise

<!-- TOOLS:END -->
