# api

Universal API tool for AI agents. Call any API from any service with a unified interface.

## Quick Start

```bash
# Admin setup (one-time)
api google admin     # Downloads credentials, enables APIs

# User login
api google auth      # Browser opens → click Allow

# Use any Google API
api google gmail users.messages.list userId=me
api google calendar events.list calendarId=primary
api google drive files.list
```

## Service Command Pattern

All services follow the same command structure:

```
api <service>
├── admin       # One-time setup (credentials, API keys, project config)
├── auth        # User authentication (OAuth, login)
├── status      # Check current auth state
├── revoke      # Remove authorization
└── <resources> # Service-specific API calls
```

This pattern provides consistency across all services - learn it once, use everywhere.

## Services

| Service | Status | Description |
|---------|--------|-------------|
| `google` | ✅ Ready | Gmail, Calendar, Drive, Sheets, Docs, etc. |
| `aws` | 🔜 Coming | S3, EC2, Lambda, etc. |
| `stripe` | 🔜 Coming | Payments, Customers, Subscriptions |
| `slack` | 🔜 Coming | Messages, Channels, Users |
| `github` | 🔜 Coming | Repos, Issues, PRs |

## Google API

### Setup

**Admin setup** (one-time, by project owner):

```bash
api google admin
```

This interactive command will:
1. Guide you to create OAuth credentials in Google Cloud Console
2. Auto-detect the downloaded `client_secret.json` from ~/Downloads
3. Enable all required APIs via gcloud (if installed)

**User login** (each user who wants to use the tool):

```bash
api google auth
# Browser opens → Sign in → Grant permissions
# Done! Token saved automatically.
```

### Usage

```bash
# List available Google services
api google services

# List methods for a service
api google gmail --list-methods
api google calendar --list-methods
api google drive --list-methods

# Get help for a specific method
api google gmail users.messages.list --help-method

# Call any method
api google <service> <method> [key=value ...]
```

### Examples

#### Gmail

```bash
# List emails
api google gmail users.messages.list userId=me

# List unread emails
api google gmail users.messages.list userId=me q="is:unread"

# Search emails
api google gmail users.messages.list userId=me q="from:boss@company.com subject:urgent"

# Get specific email
api google gmail users.messages.get userId=me id=18abc123 format=full

# Star an email
api google gmail users.messages.modify userId=me id=18abc123 --body '{"addLabelIds":["STARRED"]}'

# List labels
api google gmail users.labels.list userId=me

# Create a filter
api google gmail users.settings.filters.create userId=me --body '{
  "criteria": {"from": "newsletter@"},
  "action": {"addLabelIds": ["Label_123"], "removeLabelIds": ["INBOX"]}
}'
```

#### Calendar

```bash
# List calendars
api google calendar calendarList.list

# List today's events
api google calendar events.list calendarId=primary timeMin=$(date -u +%Y-%m-%dT00:00:00Z)

# Create event
api google calendar events.insert calendarId=primary --body '{
  "summary": "Team Meeting",
  "start": {"dateTime": "2026-01-17T14:00:00-08:00"},
  "end": {"dateTime": "2026-01-17T15:00:00-08:00"}
}'

# Check free/busy
api google calendar freebusy.query --body '{
  "timeMin": "2026-01-17T00:00:00Z",
  "timeMax": "2026-01-18T00:00:00Z",
  "items": [{"id": "primary"}]
}'
```

#### Drive

```bash
# List files
api google drive files.list

# Search files
api google drive files.list q="name contains 'report'"

# Get file info
api google drive files.get fileId=1abc123 fields=name,mimeType,webViewLink

# Export Google Doc as PDF
api google drive files.export fileId=1abc123 mimeType=application/pdf --output report.pdf

# Share a file
api google drive permissions.create fileId=1abc123 --body '{
  "role": "reader",
  "type": "user",
  "emailAddress": "alice@example.com"
}'
```

#### Sheets

```bash
# Get spreadsheet info
api google sheets spreadsheets.get spreadsheetId=1abc123

# Read cell values
api google sheets spreadsheets.values.get spreadsheetId=1abc123 range=Sheet1!A1:D10

# Write cell values
api google sheets spreadsheets.values.update spreadsheetId=1abc123 range=A1 valueInputOption=RAW --body '{
  "values": [["Name", "Email"], ["Alice", "alice@example.com"]]
}'
```

### Auth Management

```bash
# Check auth status
api google status

# Re-authorize with specific scopes
api google auth --scopes gmail,calendar

# Revoke authorization
api google revoke
```

### Available Scopes

| Scope | Access |
|-------|--------|
| `gmail` | Read, send, modify emails |
| `calendar` | Read, create, modify events |
| `drive` | Read, upload, share files |
| `sheets` | Read, write spreadsheets |
| `docs` | Read, write documents |
| `contacts` | Read contacts |
| `tasks` | Read, create tasks |

## Architecture

```
api <service> <resource> <method> [params...]
     │         │          │        │
     │         │          │        └── key=value pairs
     │         │          └── API method (list, get, create, etc.)
     │         └── Resource path (users.messages, events, files)
     └── Service (google, aws, stripe, slack)
```

### How It Works

1. **Authentication**: OAuth 2.0 with refresh tokens (authorize once, use forever)
2. **Discovery**: Methods fetched from Google's Discovery API (auto-updates)
3. **Execution**: Generic caller navigates to any method dynamically

### The Magic: Dynamic Method Navigation

```python
# "users.messages.list" → service.users().messages().list()
# "events.insert"       → service.events().insert()
# "files.export"        → service.files().export()

# No hardcoding - works with any method Google adds
```

## Configuration

```
~/.config/api/
├── google/
│   ├── client_secret.json   # OAuth credentials (from Google Console)
│   └── token.json           # User token (auto-generated)
├── aws/
│   └── credentials          # (future)
└── stripe/
    └── api_key              # (future)
```

## Troubleshooting

### "Admin setup required first"
```bash
api google admin   # Run admin setup first
```

### "Not authorized"
```bash
api google auth    # User login
```

### "Token expired"
Token auto-refreshes. If it fails:
```bash
api google auth    # Re-authorize
```

### "API not enabled"
Run admin setup again (it will enable APIs):
```bash
api google admin
```

Or enable manually at https://console.cloud.google.com/apis/library
