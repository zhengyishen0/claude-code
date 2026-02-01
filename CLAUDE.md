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
- Call APIs (calendar, gmail, drive, feishu) → subagent
- Take screenshots → subagent
- Search memory → subagent
- Edit/write files → subagent
- Run tests/scripts → subagent
- Browse websites → subagent

### The Rule

**Only read what subagents produce in this session.**

Do not directly read files, call APIs, or fetch data. Delegate first, then review the subagent's report.

### Examples

| User request | You do |
|--------------|--------|
| "What's in config.json?" | Delegate: "Read config.json and report the contents" |
| "What meetings do I have tomorrow?" | Delegate: "Check calendar for tomorrow's meetings" |
| "Fix the login bug" | Delegate: "Investigate and fix the login bug" |
| "How does the auth module work?" | Delegate: "Research the auth module and explain how it works" |
| "What's showing in Terminal?" | Delegate: "Take a screenshot of Terminal and describe it" |
| "Plan the migration" | **Direct**: Think and plan (no external data needed) |
| "Summarize what we did" | **Direct**: Synthesize from subagent reports you already have |

---

## Subagent Rules

When you are a subagent (delegated a task), follow these rules:

### 1. Parallel Tool Calls
Use parallel tool calls when possible. Don't do sequentially what can be done in parallel.

\`\`\`
Bad:  Read file1 → Read file2 → Read file3
Good: Read file1, file2, file3 (parallel)

Bad:  Fetch website1 → Fetch website2
Good: Fetch website1, website2 (parallel)
\`\`\`

### 2. No Nested Subagents
Subagents use **tools only**. Do not spawn more subagents.

\`\`\`
PM → Subagent → Tools ✅
PM → Subagent → Subagent ❌
\`\`\`

### 3. Test Before Returning
Verify your work before reporting back. Don't hand over untested results.

| Task | Test |
|------|------|
| Edit code | Run relevant tests or lint |
| Write new code | Run tests, verify it compiles |
| Fix bug | Confirm the bug is fixed |
| API call | Verify response is valid |
| Script | Confirm it ran successfully |

**Only report success if you verified it works.**

---

## Where Does Information Live?

Tell your subagents which tool to use:

| Looking for... | Tool | Examples |
|----------------|------|----------|
| Past events, appointments | \`api google calendar\` | "last summer", "dentist" |
| Emails, notifications, order status | \`api google gmail\` | "shipping update", "job reply" |
| Files in cloud storage | \`api google drive\` | "project folder" |
| Spreadsheet data | \`api google sheets\` | "Q4 budget" |
| Bitable/多维表格 data | \`service feishu bitable\` | "student info", "records" |
| Facts from past sessions | \`memory search\` | "laptop spec", "API key" |
| How/why we did something | \`memory --recall\` | "OAuth approach", "progress on X" |
| What's on screen (any app) | \`screenshot\` | "Figma", "Terminal" |
| Interact with websites | \`browser\` | "buy VPS", "book flight" |
| Code changes | \`jj workspace\` first | "fix bug", "add feature" |

## Quick Rules

1. **"What did I do..."** → Calendar, not memory
2. **"Updates on..."** → Gmail (notifications come via email)
3. **"What was the [fact]"** → \`memory search\`
4. **"How did we..."** → \`memory --recall\`
5. **Code changes** → Create workspace first

## Workflow

Main branch is protected. **Must work in a jj workspace** (not default).

### Start work
\`\`\`bash
jj workspace add --name <task> ../.workspaces/claude-code/<task>
cd ../.workspaces/claude-code/<task>
jj new main -m "<task description>"
# Now you can edit files
\`\`\`

### Finish work (from workspace)
\`\`\`bash
jj describe -m "final: <summary>"     # Ensure good description
\`\`\`

### Merge to main (from main repo)
\`\`\`bash
cd /path/to/main/repo
jj new main <change-id> -m "merge: <description>"  # Creates merge commit
jj squash                                           # Squash into main
jj workspace forget <task>                          # Cleanup workspace
rm -rf ../.workspaces/claude-code/<task>           # Cleanup files
\`\`\`

### Abandon work
\`\`\`bash
jj abandon                            # Discard current change
jj workspace forget <task>            # Remove workspace
\`\`\`

## Tools Reference (for subagents)

### jj (version control)
\`\`\`bash
# Workspace (required for edits)
jj workspace add --name <n> <path>   # Create workspace
jj workspace list                     # List workspaces
jj workspace forget <name>            # Remove workspace

# Changes
jj new main -m "description"          # Start new change from main
jj log                                # See history
jj status                             # See current changes
jj describe -m "message"              # Update description
jj abandon                            # Discard change

# Merging
jj new main <change> -m "merge: X"    # Merge change into main (creates merge commit)
jj squash                             # Squash working copy into parent
\`\`\`

### browser
\`\`\`bash
browser open <url>                    # Open URL
browser click <selector> (--index N)  # Click element
browser input <selector> <value>      # Type into field
browser sendkey <key>                 # Send key (enter, esc, tab, arrows)
browser snapshot                      # Page accessibility tree
browser selector                      # List clickable elements with CSS selectors
browser account                       # Saved accounts
browser password                      # Saved passwords
browser execute <js>                  # Run JS in page (last resort)
\`\`\`

**Rules:** Use CSS selectors only. Run \`selector\` before clicking to find valid targets.

### screenshot
\`\`\`bash
screenshot <app-name>
\`\`\`

### memory
\`\`\`bash
memory search "keywords"
memory search "keywords" --recall "question"
\`\`\`

### api
\`\`\`bash
api google calendar events.list calendarId=primary
api google gmail users.messages.list userId=me q="query"
api google drive files.list q="name contains 'X'"
api google sheets spreadsheets.get spreadsheetId=<id>
\`\`\`

### gmail plugins

Custom actions for Gmail (parallel batch operations):

\`\`\`bash
# Forward
api google gmail forward '[{"id": "x", "to": "a@b.com", "cc": "c@d.com", "note": "FYI"}]'

# Reply
api google gmail reply '[{"id": "x", "body": "Thanks!", "reply_all": true}]'

# Compose (send)
api google gmail compose '[{"to": "a@b.com", "subject": "Hello", "body": "Message here"}]'

# Compose (draft)
api google gmail compose '[{"to": "a@b.com", "subject": "Hello", "body": "Message here", "draft": true}]'
\`\`\`

| Command | Required | Optional |
|---------|----------|----------|
| \`forward\` | \`id\`, \`to\` | \`cc\`, \`note\` |
| \`reply\` | \`id\`, \`body\` | \`reply_all\` |
| \`compose\` | \`to\`, \`subject\`, \`body\` | \`cc\`, \`bcc\`, \`html\`, \`draft\` |

### feishu

Feishu/Lark APIs for Bitable, IM, Calendar, and VC.

\`\`\`bash
# Setup
service feishu admin              # Configure app credentials
service feishu status             # Check configuration

# Run bot
service feishu bot start          # Start IM bot listener
\`\`\`

### feishu bitable

Query and manage Bitable (多维表格) data:

\`\`\`bash
# List tables in a base
service feishu bitable list_tables app_token=PF9RbSWI8aqa3hs9AXzcyCcSntc

# List fields (columns) in a table
service feishu bitable list_fields app_token=xxx table_id=tblXXX

# List records (with optional filter)
service feishu bitable list_records app_token=xxx table_id=tblXXX page_size=50

# Get single record
service feishu bitable get_record app_token=xxx table_id=tblXXX record_id=recXXX

# Create record
service feishu bitable create_record app_token=xxx table_id=tblXXX data='{"fields":{"Name":"Alice"}}'

# Update record
service feishu bitable update_record app_token=xxx table_id=tblXXX record_id=recXXX data='{"fields":{"Name":"Bob"}}'

# Delete record
service feishu bitable delete_record app_token=xxx table_id=tblXXX record_id=recXXX
\`\`\`

| Command | Required | Optional |
|---------|----------|----------|
| \`list_tables\` | \`app_token\` | - |
| \`list_fields\` | \`app_token\`, \`table_id\` | - |
| \`list_records\` | \`app_token\`, \`table_id\` | \`page_size\`, \`filter\` |
| \`get_record\` | \`app_token\`, \`table_id\`, \`record_id\` | - |
| \`create_record\` | \`app_token\`, \`table_id\`, \`data\` | - |
| \`update_record\` | \`app_token\`, \`table_id\`, \`record_id\`, \`data\` | - |
| \`delete_record\` | \`app_token\`, \`table_id\`, \`record_id\` | - |

### feishu im

Send messages via the Feishu bot:

\`\`\`bash
# Send text message
service feishu im send chat_id=oc_xxx text="Hello!"

# Send interactive card
service feishu im send_card chat_id=oc_xxx card='{"elements":[...]}'

# Reply to a message
service feishu im reply message_id=om_xxx text="Got it!"

# List chats bot is in
service feishu im list_chats

# Get bot info
service feishu im bot_info
\`\`\`

| Command | Required | Optional |
|---------|----------|----------|
| \`send\` | \`chat_id\`, \`text\` | - |
| \`send_card\` | \`chat_id\`, \`card\` | - |
| \`reply\` | \`message_id\`, \`text\` | - |
| \`list_chats\` | - | - |
| \`bot_info\` | - | - |

### feishu vc

Video conference statistics:

\`\`\`bash
# Top users by meeting time
service feishu vc top_users days=30 limit=10

# Aggregate meeting stats
service feishu vc meeting_stats days=7
\`\`\`

| Command | Required | Optional |
|---------|----------|----------|
| \`top_users\` | - | \`days\` (default 30), \`limit\` (default 10) |
| \`meeting_stats\` | - | \`days\` (default 30) |

## Setup

\`\`\`bash
./setup all
./setup shell
\`\`\`
