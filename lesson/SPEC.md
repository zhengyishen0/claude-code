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
│  Trust model:                                           │
│    AI drafts lessons (auto-saved)                       │
│    Human can mark wrong or promote                      │
│    True by default unless human says wrong              │
│                                                         │
│  Hierarchy:                                             │
│    Tools/Skills = stable, human-verified                │
│    Lessons = dynamic, AI-learned, can be wrong          │
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
# Full pattern (recommended)
lesson add "WHEN editing config files -> DO read first -> BECAUSE understand existing structure"

# With explicit scope
lesson add --scope=tmux "WHEN editing -> DO read first -> BECAUSE avoid wrong assumptions"

# Structured flags (compiles to pattern)
lesson add -w "editing config files" -d "read first" -b "understand existing structure"
lesson add -w "user is debugging" --dont "suggest refactors" -b "breaks focus"

# Mark as user-stated (higher confidence)
lesson add --firm "WHEN multiple approaches -> DO pick minimal -> BECAUSE user preference"
```

**Flags:**
- `-w, --when` — The trigger/context
- `-d, --do` — The action to take
- `--dont` — The action to avoid (mutually exclusive with --do)
- `-b, --because` — The reason
- `-s, --scope` — Tool/skill this applies to (default: global)
- `--firm` — User-stated, won't be questioned

### `lesson list`

List all lessons.

```bash
lesson list                    # All active lessons
lesson list --scope=tmux       # Lessons for tmux
lesson list --scope=global     # Global lessons only
lesson list --from=ai          # AI-drafted only
lesson list --from=user        # User-stated only
lesson list --all              # Include deleted/promoted
```

**Output:**

```
ID   SCOPE    FROM  PATTERN
001  global   user  WHEN multiple approaches -> DO pick minimal -> BECAUSE user preference
002  tmux     ai    WHEN editing tmux.conf -> DO read first -> BECAUSE avoid wrong assumptions
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
scope: tmux
from: ai
status: active
created: 2024-02-10
pattern: "WHEN editing tmux.conf -> DO read first -> BECAUSE avoid wrong assumptions"
parsed:
  when: "editing tmux.conf"
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

Promote a validated lesson to a skill or tool definition.

```bash
lesson promote 002 --to=skill/config-edit   # Add to skill
lesson promote 002 --to=tool/tmux           # Add to tool context
```

This appends the lesson to the target file and marks it as promoted.

### `lesson search <query>`

Search lessons by keyword.

```bash
lesson search "tmux"
lesson search "config" --scope=global
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
{"id":"001","scope":"global","from":"user","status":"active","created":"2024-02-10","when":"multiple approaches","action":"do","do":"pick minimal","because":"user preference"}
{"id":"002","scope":"tmux","from":"ai","status":"active","created":"2024-02-10","when":"editing tmux.conf","action":"do","do":"read first","because":"avoid wrong assumptions"}
{"id":"002","scope":"tmux","from":"ai","status":"deleted","updated":"2024-02-11","reason":"too specific"}
```

Append-only log allows tracking history. Latest entry per ID wins.

---

## Loading Lessons

Lessons are loaded contextually based on scope:

```bash
# When AI starts a session
lesson load                    # Loads global lessons

# When AI uses a tool
lesson load --scope=tmux       # Loads global + tmux lessons

# When AI runs a skill
lesson load --scope=research   # Loads global + research lessons
```

**Output format (for AI consumption):**

```markdown
## Lessons (3 active)

### Global
- WHEN multiple approaches -> DO pick minimal -> BECAUSE user preference [firm]

### tmux
- WHEN editing tmux.conf -> DO read first -> BECAUSE avoid wrong assumptions
- WHEN debugging tmux -> DO NOT kill server -> BECAUSE destroys user sessions
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
3. V drafts: lesson add --scope=X "WHEN ... -> DO ... -> BECAUSE ..."
4. Lesson saved (active, from=ai)
5. Future sessions load this lesson
```

---

## Schema

```typescript
interface Lesson {
  id: string;              // Unique ID (incrementing)
  scope: string;           // "global" | tool name | skill name
  from: "ai" | "user";     // Who created it
  status: "active" | "promoted" | "deleted";
  created: string;         // ISO date
  updated?: string;        // ISO date (if modified)

  // The pattern (parsed)
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
# AI drafts lesson automatically:

$ lesson add --scope=tmux \
  "WHEN editing tmux.conf -> DO read first -> BECAUSE user corrected: was layering on wrong assumptions"

# Next session: AI loads lesson
$ lesson load --scope=tmux
## Lessons (1 active)
- WHEN editing tmux.conf -> DO read first -> BECAUSE user corrected: was layering on wrong assumptions

# AI reads tmux.conf before editing ✓
```

### Workflow: User marks lesson wrong

```bash
$ lesson list
ID   SCOPE   FROM  PATTERN
005  browser ai    WHEN page slow -> DO wait 5s -> BECAUSE avoid timeout

$ lesson wrong 005 --reason "too long, 2s is enough"
Deleted lesson 005

# User could add correct version:
$ lesson add --scope=browser --firm \
  "WHEN page slow -> DO wait 2s -> BECAUSE 5s too long"
```

### Workflow: Promote to skill

```bash
$ lesson list --scope=config
ID   SCOPE   FROM  PATTERN
002  config  ai    WHEN editing any config -> DO read first -> BECAUSE understand structure
007  config  ai    WHEN config syntax error -> DO show diff -> BECAUSE user needs to see what changed

# These are solid patterns - promote to skill
$ lesson promote 002 --to=skill/config-edit
$ lesson promote 007 --to=skill/config-edit

# Now they're part of the skill definition, not just lessons
```

---

## CLI Summary

```
lesson add <pattern>              Add a lesson
lesson add -w -d/-dont -b         Add with structured flags
lesson list [--scope] [--from]    List lessons
lesson show <id>                  Show lesson details
lesson wrong <id>                 Mark as incorrect (delete)
lesson promote <id> --to=<path>   Promote to skill/tool
lesson search <query>             Search lessons
lesson load [--scope]             Load lessons for AI context
```

---

## Design Principles

1. **Behavioral, not factual** — Lessons are WHEN->DO->BECAUSE rules, not "user likes X"
2. **True by default** — AI-drafted lessons are active immediately
3. **Human override** — `lesson wrong` deletes, `lesson promote` elevates
4. **Scoped loading** — Only load relevant lessons to avoid noise
5. **Append-only log** — Full history preserved
6. **FP-style pattern** — Parseable, composable, testable
