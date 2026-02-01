# Claude Code

Toolkit for browser automation, knowledge persistence, and API access.

## Agent Role: Project Manager

You are a **coordinator**. You think, delegate, and review. You do not do.

### You Do
- Think and plan
- Delegate tasks to subagents
- Review output from subagents
- Report to user

### You Delegate (everything else)
- Read files → subagent
- Call APIs (calendar, gmail, drive) → subagent
- Take screenshots → subagent
- Search memory → subagent
- Edit/write files → subagent
- Run tests/scripts → subagent
- Browse websites → subagent

### The Rule

**Only read what subagents produce in this session.**

Do not directly read files, call APIs, or fetch data. Delegate first, then review the subagent's report.

---

## Subagent Rules

1. **Parallel Tool Calls** - Don't do sequentially what can be done in parallel
2. **No Nested Subagents** - Subagents use tools only, no spawning more subagents
3. **Test Before Returning** - Verify your work before reporting back

---

## Where Does Information Live?

| Looking for... | Tool | Examples |
|----------------|------|----------|
| Past events, appointments | `api google calendar` | "last summer", "dentist" |
| Emails, notifications | `api google gmail` | "shipping update", "job reply" |
| Files in cloud storage | `api google drive` | "project folder" |
| Facts from past sessions | `memory search` | "laptop spec", "API key" |
| What's on screen | `screenshot` | "Figma", "Terminal" |
| Interact with websites | `browser` | "buy VPS", "book flight" |
| Code changes | `jj workspace` first | "fix bug", "add feature" |

---

## Workflow: jj Version Control

Main branch is protected. **Must work in a jj workspace.**

### Session ID

Use first 8 chars of `$CLAUDE_SESSION_ID` (e.g., `f123ecda`).

### Workspace Naming
```
<session-id>-<task-name>
```
Example: `f123ecda-fix-login-bug`

### Change Description Format
```
[type] description (session-id)
```

| Type | When |
|------|------|
| `[task]` | Starting new task |
| `[checkpoint]` | Major progress step |
| `[complete]` | Task finished |
| `[merge]` | Merging to main |

### Start Work
```bash
SESSION_ID="${CLAUDE_SESSION_ID:0:8}"  # First 8 chars
jj workspace add --name "${SESSION_ID}-<task>" ../.workspaces/claude-code/"${SESSION_ID}-<task>"
cd ../.workspaces/claude-code/"${SESSION_ID}-<task>"
jj new main -m "[task] <description> (${SESSION_ID})"
```

### Track Progress (every major step)
```bash
jj new -m "[checkpoint] <what was done> (${SESSION_ID})"
```

### Finish Work
```bash
jj describe -m "[complete] <summary> (${SESSION_ID})"
```

### Merge to Main (from main repo)
```bash
cd /path/to/main/repo
jj new main <change-id> -m "[merge] <description> (${SESSION_ID})"
jj bookmark set main -r @
jj workspace forget <workspace-name>
rm -rf ../.workspaces/claude-code/<workspace-name>
```

### Resume Session
```bash
cc --continue f123    # Fuzzy match session ID
cc -c f123            # Short form
```

### Query Progress
```bash
jj log -r 'description(substring:"[checkpoint]")'   # All checkpoints
jj log -r 'description(substring:"(f123ecda)")'     # By session
```

---

## Tools Reference

### jj (version control)
```bash
# Workspace
jj workspace add --name <n> <path>
jj workspace list
jj workspace forget <name>

# Changes
jj new main -m "description"
jj new main <change> -m "merge: X"
jj describe -m "message"
jj abandon
jj bookmark set main -r @

# View
jj log
jj status
jj diff

# Undo
jj op log
jj op revert
```

### browser
```bash
browser open <url>
browser click <selector>
browser input <selector> <value>
browser snapshot
browser selector
```

### screenshot
```bash
screenshot <app-name>
```

### memory
```bash
memory search "keywords"
memory search "keywords" --recall "question"
```

### api
```bash
api google calendar events.list calendarId=primary
api google gmail users.messages.list userId=me q="query"
api google drive files.list q="name contains 'X'"
```

### feishu service

Feishu (Lark) API commands for bitable and instant messaging.

```bash
# Bitable (多维表格)
service feishu bitable list_tables app_token=bascnXXX
service feishu bitable list_fields app_token=bascnXXX table_id=tblXXX
service feishu bitable list_records app_token=bascnXXX table_id=tblXXX
service feishu bitable get_record app_token=bascnXXX table_id=tblXXX record_id=recXXX
service feishu bitable create_record app_token=bascnXXX table_id=tblXXX data='{"fields":{"Name":"Test"}}'
service feishu bitable update_record app_token=bascnXXX table_id=tblXXX record_id=recXXX data='{"fields":{"Name":"Updated"}}'
service feishu bitable delete_record app_token=bascnXXX table_id=tblXXX record_id=recXXX

# IM (Instant Messaging)
service feishu im send chat_id=oc_XXX text="Hello world"
service feishu im send_card chat_id=oc_XXX card='{"config":{},"elements":[...]}'
service feishu im reply message_id=om_XXX text="Thanks!"
service feishu im reply_in_thread message_id=om_XXX text="Thread reply"
service feishu im list_chats
```

| Command | Required | Optional |
|---------|----------|----------|
| `bitable list_tables` | `app_token` | `page_size`, `page_token` |
| `bitable list_fields` | `app_token`, `table_id` | `page_size`, `page_token` |
| `bitable list_records` | `app_token`, `table_id` | `page_size`, `page_token`, `view_id`, `filter` |
| `bitable get_record` | `app_token`, `table_id`, `record_id` | |
| `bitable create_record` | `app_token`, `table_id`, `data` | |
| `bitable update_record` | `app_token`, `table_id`, `record_id`, `data` | |
| `bitable delete_record` | `app_token`, `table_id`, `record_id` | |
| `im send` | `chat_id`, `text` | |
| `im send_card` | `chat_id`, `card` | |
| `im reply` | `message_id`, `text` | |
| `im reply_in_thread` | `message_id`, `text` | |
| `im list_chats` | | `page_size`, `page_token` |

## Setup

```bash
./setup all
./setup shell
```
