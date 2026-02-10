# Lesson Tool Specification

A CLI tool for AI to learn behavioral rules from experience.

---

## TL;DR

```
┌─────────────────────────────────────────────────────────┐
│  Lessons are behavioral rules, not facts.               │
│                                                         │
│  Pattern:                                               │
│    WHEN [context] -> DO [action] -> BECAUSE [reason]    │
│    WHEN [context] -> DO NOT [action] -> BECAUSE [reason]│
│                                                         │
│  Ownership:                                             │
│    --skill=X    Skill auto-loads its lessons            │
│    (no flag)    Global, always loaded                   │
│                                                         │
│  Source (auto-detected):                                │
│    Human runs command → from=user (authoritative)       │
│    AI runs command    → from=ai (can be wrong)          │
│                                                         │
│  Lifecycle:                                             │
│    AI drafts → active → human: wrong | promote          │
└─────────────────────────────────────────────────────────┘
```

---

## The Pattern

Every lesson follows this structure:

```
WHEN [trigger/context]
-> DO [action]           # or DO NOT
-> BECAUSE [reason]
```

**Examples:**

```bash
# Positive (DO)
"WHEN editing tmux.conf -> DO read first -> BECAUSE avoid layering mistakes on wrong assumptions"

# Negative (DO NOT)
"WHEN user is debugging -> DO NOT suggest unrelated refactors -> BECAUSE breaks focus"

# Compact form
"WHEN [tmux.conf edit] -> DO [read first] -> BECAUSE [avoid wrong assumptions]"
```

---

## Commands

### `lesson add`

Add a new lesson.

```bash
# Global (always loaded)
lesson add "WHEN multiple approaches -> DO pick minimal -> BECAUSE user preference"

# Skill-scoped (auto-loads when skill runs)
lesson add --skill=config "WHEN editing -> DO read first -> BECAUSE avoid wrong assumptions"
lesson add --skill=browser "WHEN navigation fails -> DO snapshot first -> BECAUSE see current state"
```

**Flags:**
- `--skill` — Skill this applies to (default: global, always loaded)

**Source detection:**
- Human runs `lesson add` in terminal → `from: user` (authoritative)
- AI runs `lesson add` via tool → `from: ai` (can be wrong)

No flag needed. The tool detects who called it.

### `lesson list`

List all lessons.

```bash
lesson list                    # All active lessons
lesson list --skill=config     # Lessons for config skill
lesson list --global           # Global lessons only
lesson list --from=ai          # AI-learned only
lesson list --from=user        # User-stated only
lesson list --all              # Include deleted/promoted
```

**Output:**

```
ID   SKILL    FROM  PATTERN
001  global   user  WHEN multiple approaches -> DO pick minimal -> BECAUSE user preference
002  config   ai    WHEN editing config -> DO read first -> BECAUSE avoid wrong assumptions
003  browser  ai    WHEN navigation fails -> DO snapshot first -> BECAUSE see current state
```

### `lesson show <id>`

Show full lesson details.

```bash
lesson show 002
```

**Output:**

```yaml
id: 002
skill: config
from: ai
status: active
created: 2024-02-10
pattern: "WHEN editing config -> DO read first -> BECAUSE avoid wrong assumptions"
parsed:
  when: "editing config"
  action: do
  do: "read first"
  because: "avoid wrong assumptions"
```

### `lesson wrong <id>`

Mark a lesson as incorrect. Deletes it.

```bash
lesson wrong 002                          # Delete lesson
lesson wrong 002 --reason "too specific"  # With reason (for learning)
```

### `lesson promote <id>`

Bake a validated lesson into a skill's definition.

```bash
lesson promote 002 --to=config    # Append to config skill's SKILL.md
```

This appends the lesson to the skill's SKILL.md and marks it as promoted.

### `lesson search <query>`

Search lessons by keyword.

```bash
lesson search "config"
lesson search "editing" --skill=config
```

---

## Storage

Lessons stored in `~/.claude/lessons/`:

```
~/.claude/lessons/
├── lessons.jsonl          # All lessons (append-only log)
├── index.json             # Quick lookup index
└── promoted/              # Promoted lessons (reference)
    └── 002.md
```

**lessons.jsonl format:**

```jsonl
{"id":"001","skill":"global","from":"user","status":"active","created":"2024-02-10","when":"multiple approaches","action":"do","do":"pick minimal","because":"user preference"}
{"id":"002","skill":"config","from":"ai","status":"active","created":"2024-02-10","when":"editing config","action":"do","do":"read first","because":"avoid wrong assumptions"}
{"id":"002","skill":"config","from":"ai","status":"deleted","updated":"2024-02-11","reason":"too specific"}
```

Append-only log allows tracking history. Latest entry per ID wins.

---

## Loading Lessons

Skills auto-load their lessons. No manual loading needed.

```markdown
# In skill definition (e.g., ~/.claude/commands/config/SKILL.md)

## Lessons
$(lesson load --skill=config)

## Steps
1. Read the file first
...
```

**When skill runs:**
1. Skill loads global lessons (always)
2. Skill loads its own scoped lessons (via `lesson load --skill=X`)
3. AI has full context before acting

**Output format (for AI consumption):**

```markdown
## Lessons (3 active)

### Global
- WHEN multiple approaches -> DO pick minimal -> BECAUSE user preference [user]

### config
- WHEN editing config -> DO read first -> BECAUSE avoid wrong assumptions
- WHEN config error -> DO NOT retry blindly -> BECAUSE show diff first
```

---

## Integration with IVDX

Lessons fit into the IVDX framework:

| Phase | Lesson Role |
|-------|-------------|
| V (validate) | Load relevant lessons before evaluating |
| X (execute) | Load relevant lessons before acting |
| V (verify) | If error matches a lesson, apply it |
| V (verify) | If new pattern discovered, draft lesson |

**Auto-drafting lessons:**

When V detects a correction pattern:

```
1. User corrects AI behavior
2. V recognizes: "This is a learnable pattern"
3. V drafts: lesson add --skill=X "WHEN ... -> DO ... -> BECAUSE ..."
4. Lesson saved (active, from=ai)
5. Future skill invocations load this lesson
```

---

## Schema

```typescript
interface Lesson {
  id: string;              // Unique ID (incrementing)
  skill: string;           // "global" | skill name
  from: "ai" | "user";     // Auto-detected: who ran the command
  status: "active" | "promoted" | "deleted";
  created: string;         // ISO date
  updated?: string;        // ISO date (if modified)

  // The pattern (parsed from FP text)
  when: string;            // Trigger/context
  action: "do" | "dont";   // Positive or negative
  do: string;              // The action
  because: string;         // The reason

  // Metadata
  reason?: string;         // Why deleted/promoted
  promoted_to?: string;    // Where promoted
}
```

---

## Examples

### Workflow: AI learns from correction

```bash
# Session: User corrects AI for not reading config first
# AI drafts lesson automatically (from=ai):

$ lesson add --skill=config "WHEN editing config -> DO read first -> BECAUSE was layering on wrong assumptions"

# Next session: /config skill loads its lessons automatically
# AI reads config before editing ✓
```

### Workflow: User marks lesson wrong

```bash
$ lesson list
ID   SKILL   FROM  PATTERN
005  browser ai    WHEN page slow -> DO wait 5s -> BECAUSE avoid timeout

$ lesson wrong 005 --reason "too long, 2s is enough"
Deleted lesson 005

# User adds correct version (from=user, authoritative):
$ lesson add --skill=browser "WHEN page slow -> DO wait 2s -> BECAUSE 5s too long"
```

### Workflow: Promote to skill

```bash
$ lesson list --skill=config
ID   SKILL   FROM  PATTERN
002  config  ai    WHEN editing any config -> DO read first -> BECAUSE understand structure
007  config  ai    WHEN config syntax error -> DO show diff -> BECAUSE user needs to see what changed

# These are solid patterns - bake into skill definition
$ lesson promote 002 --to=config
$ lesson promote 007 --to=config

# Now they're part of the skill's SKILL.md, not dynamic lessons
```

---

## CLI Summary

```
lesson add <pattern>              Add a lesson (FP text only)
lesson add --skill=X <pattern>    Add a skill-scoped lesson
lesson list [--skill=X] [--from]  List lessons
lesson show <id>                  Show lesson details
lesson wrong <id>                 Mark as incorrect (delete)
lesson promote <id> --to=<skill>  Bake into skill definition
lesson search <query>             Search lessons
lesson load --skill=X             Load lessons (called by skills)
```

---

## Design Principles

1. **Behavioral, not factual** — Lessons are WHEN->DO->BECAUSE rules, not "user likes X"
2. **True by default** — AI-drafted lessons are active immediately
3. **Human override** — `lesson wrong` deletes, `lesson promote` elevates
4. **Skill-scoped** — Skills auto-load their lessons, no manual loading
5. **Source detection** — AI vs user determined by who runs the command
6. **Append-only log** — Full history preserved
7. **FP-style pattern** — Parseable, composable, testable
