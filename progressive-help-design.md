# Progressive Help Design for Claude Tools

## Overview

This document outlines the design decisions for implementing a progressive help system for claude-tools, optimized for LLM consumption (especially smaller models).

## Problem Statement

Current approach front-loads all tool documentation in CLAUDE.md, which:
- Consumes significant context window space
- Loads information before it's needed
- Can cause confusion for smaller models
- Requires manual synchronization between CLAUDE.md and tool help

## Solution: Hybrid Progressive Help Pattern

### Core Principle

**Progressive Instruction**: Deliver detailed documentation when tools are actually invoked, not upfront.

### Design Decisions

#### 1. Hybrid Approach

**CLAUDE.md (Front-loaded - "Just Enough to Choose & Plan")**
- One-line tool capability statement
- Brief list of commands (for quick reference)
- When to use which tool
- Entry point reference: `Run claude-tools <tool> for help`

**Tool Help (Progressive - "Everything Needed to Execute")**
- Detailed command syntax
- All flags and parameters
- Comprehensive examples
- Key principles and guidelines
- Usage notes

**Rationale**:
- Reduces initial context for LLMs
- Prevents hallucination by providing instructions just-in-time
- Forces correct behavior (help is authoritative source)
- Smaller models get guidance when they need it

#### 2. Structured Metadata Format (YAML)

**Decision**: Use `metadata.yaml` as single source of truth for each tool

**Location**: `claude-tools/<tool>/metadata.yaml`

**Schema**:
```yaml
name: string              # Tool name (must match directory)
description: string       # One-line description for CLAUDE.md

commands:
  category:               # primary, secondary, utility, etc.
    - name: string        # Command name
      brief: string       # Short description
      args: string        # Arguments (optional)
      flags:              # Flags (optional)
        - name: string
          brief: string

options:                  # Global options (optional)
  - name: string
    brief: string

examples:                 # Usage examples
  - string

principles:               # Key principles/guidelines
  - string

notes:                    # Additional notes
  - string
```

**Benefits**:
- ✅ Single source of truth
- ✅ Enforced structure (YAML schema validation)
- ✅ Easy parsing for auto-generation
- ✅ Consistent format across all tools
- ✅ Human-readable and editable

#### 3. Shared Help Rendering Library

**Decision**: Create `claude-tools/lib/help.sh` for rendering help from YAML

**Functions**:
- `load_metadata(path)` - Validates and loads YAML file
- `show_help(path)` - Renders formatted help message
- `get_commands(path)` - Extracts command names
- `get_description(path)` - Extracts description
- `get_summary(path)` - Generates CLAUDE.md one-liner

**Why**:
- DRY principle - no duplicated help rendering code
- Consistent output formatting
- Easy to update format across all tools
- Each tool's run.sh stays clean (implementation only)

#### 4. Validation Tool

**Decision**: Add `claude-tools validate` command

**Checks**:
- ✅ metadata.yaml exists
- ✅ YAML syntax is valid
- ✅ Required fields present (name, description, commands)
- ✅ run.sh exists and is executable
- ✅ Consistent formatting

**Usage**:
```bash
claude-tools validate              # Check all tools
claude-tools validate chrome       # Check specific tool
```

**Benefits**:
- Enforces standardization
- Catches errors before they break tools
- Can be used in CI/CD

#### 5. Auto-Generation in Sync

**Decision**: Update `claude-tools sync` to generate CLAUDE.md from metadata.yaml

**Process**:
1. Scan all `claude-tools/*/metadata.yaml` files
2. Extract name, description, commands using `get_summary()`
3. Generate minimal CLAUDE.md entries
4. Replace content between `<!-- TOOLS:AUTO-GENERATED -->` markers

**Benefits**:
- Single source of truth (metadata.yaml)
- No manual updates needed
- Consistency guaranteed

## CLAUDE.md Format (Minimal)

```markdown
## Available Tools

Run `claude-tools <tool>` for full help.

- **chrome** - Browser automation | `open` `click` `input` `wait` `snapshot` `inspect`
- **documentation** - External docs | `library` `command` `api`
- **environment** - Event log | `check` `event`
- **memory** - Search past sessions | `search` `recall`
- **screenshot** - Capture windows | `<app_name>` `--list`
- **worktree** - Git worktrees | `create` `list` `remove`
```

**Key characteristics**:
- One line per tool
- Pipe-separated: description | commands
- Commands show what's available at a glance
- No detailed syntax (use progressive help)

## Tool Help Format (Comprehensive)

```
toolname - Description

Usage: toolname [OPTIONS] <command> [args...]

COMMANDS:
  PRIMARY:
    command1          Brief description
    command2          Brief description

  SECONDARY:
    command3          Brief description

OPTIONS:
  --flag VALUE      Description

EXAMPLES:
  toolname command1 "example"
  toolname command2 --flag value

KEY PRINCIPLES:
  1. Principle one - explanation
  2. Principle two - explanation

NOTES:
  - Note one
  - Note two
```

## Implementation Workflow

1. **Create metadata.yaml** for each tool
2. **Update run.sh** to use `lib/help.sh`:
   ```bash
   source "$(dirname "$0")/../lib/help.sh"
   if [ $# -eq 0 ]; then
     show_help "$(dirname "$0")/metadata.yaml"
     exit 0
   fi
   ```
3. **Run validate** to ensure compliance
4. **Run sync** to update CLAUDE.md
5. **Test** the tool end-to-end

## Trade-offs

### What We Gain
- ✅ Massive token savings upfront
- ✅ Always-fresh documentation (from tool itself)
- ✅ Forces correct behavior (help is authoritative)
- ✅ Less hallucination (smaller context = less confusion)
- ✅ Enforced consistency

### What We Accept
- Extra round-trip on first use (run help, then run command)
- Requires `yq` as dependency
- Cross-tool workflows still need documentation in CLAUDE.md

## Tool Design Principles (Enforced)

When creating tools:
1. **No args = help** - Running without arguments MUST show help
2. **Metadata-driven** - All documentation in metadata.yaml
3. **Standard entry point** - Each tool uses `run.sh`
4. **Use shared library** - Source `lib/help.sh` for help rendering
5. **Validate compliance** - Run `claude-tools validate` before committing

## Success Criteria

- [ ] All tools have metadata.yaml
- [ ] All tools use lib/help.sh
- [ ] CLAUDE.md is auto-generated from metadata
- [ ] Running tool with no args shows help from YAML
- [ ] `claude-tools validate` passes for all tools
- [ ] CLAUDE.md tool section < 50 lines (vs current ~80)
