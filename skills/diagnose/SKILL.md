---
name: diagnose
description: Fast linting tool for uncommitted files. Runs shellcheck, ruff, eslint, etc. Use to check code quality before committing.
---

# Diagnose Tool

Fast per-file diagnostics for uncommitted files. Silent on success, shows errors only.

## Command

```bash
diagnose [--verbose]
```

## What It Checks

| Language | Tool |
|----------|------|
| Shell (*.sh) | shellcheck |
| Python (*.py) | ruff |
| JavaScript (*.js) | eslint |
| TypeScript (*.ts) | eslint |
| Go (*.go) | go vet |
| JSON (*.json) | jq |
| YAML (*.yaml) | yamllint |
| C/C++ | cppcheck |
| Markdown | yamllint (frontmatter only) |

## Behavior

- Automatically detects file types from extension or shebang
- Only checks uncommitted files (from `git status`)
- Batches files by type for efficiency
- 30 second timeout to prevent hangs

## When to Use

- Before committing changes
- After writing new code
- To verify code quality

## Output

- Silent if no errors (just "diagnose" at end)
- Shows errors with file paths and line numbers
- Use `--verbose` to see success messages
