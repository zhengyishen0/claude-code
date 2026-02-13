---
name: google
description: Google APIs (Gmail, Calendar, Drive, Sheets). Use when user needs to access Google services, read emails, manage calendar, or work with Google Docs/Sheets.
---

# Google API

Access Google services via CLI.

## Commands

```bash
service google status                    # Check auth status
service google auth                      # Authorize (opens browser)
service google services                  # List available services
service google <service> <method> [params...]
```

## Available Services

| Service | Example Methods |
|---------|-----------------|
| gmail | users.messages.list, users.messages.get |
| calendar | events.list, events.insert |
| drive | files.list, files.get |
| sheets | spreadsheets.get, spreadsheets.values.get |
| docs | documents.get |
| tasks | tasklists.list, tasks.list |
| contacts | people.connections.list |

## Examples

```bash
# Gmail - list unread
service google gmail users.messages.list userId=me q="is:unread"

# Gmail - read specific message
service google gmail users.messages.get userId=me id=MESSAGE_ID

# Calendar - list events
service google calendar events.list calendarId=primary

# Drive - list files
service google drive files.list

# Sheets - get values
service google sheets spreadsheets.values.get spreadsheetId=ID range="Sheet1!A1:B10"
```

## First Time Setup

1. Run `service google auth`
2. Browser opens for Google login
3. Grant permissions
4. Done - APIs now accessible
