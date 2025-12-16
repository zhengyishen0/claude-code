# documentation

Get external documentation for libraries, commands, and APIs

## Quick Start

```bash
# Set up Context7 API key (one-time, for library docs)
claude-tools documentation config context7 'your-key'

# Get library documentation
claude-tools documentation library vercel/next.js --topic routing

# Get CLI command examples
claude-tools documentation command tar

# Get API specifications
claude-tools documentation api stripe.com
```

## Commands

### library

Get library/package documentation via Context7 API

```bash
library <library-id> [--topic <topic>] [--version <version>] [--format txt|json]
```

**Examples:**
```bash
# Get Next.js routing documentation
claude-tools documentation library vercel/next.js --topic routing

# Get React hooks documentation
claude-tools documentation library reactjs/react.dev --topic hooks

# Get Express middleware examples
claude-tools documentation library expressjs/express --topic middleware

# Get specific version
claude-tools documentation library vercel/next.js --version v15.1.8 --topic "server actions"

# Get JSON output
claude-tools documentation library vercel/next.js --topic routing --format json
```

**How to find library IDs:**

1. Visit https://context7.com/dashboard and search
2. Library IDs follow format: `owner/repo` (e.g., `vercel/next.js`)

**Common topics:**
- routing, hooks, middleware, authentication, state management
- "server actions", "app router", "api routes"

### command

Get CLI command examples via cheat.sh

```bash
command <command-name>
```

**Examples:**
```bash
# CLI commands
claude-tools documentation command tar
claude-tools documentation command git
claude-tools documentation command docker
claude-tools documentation command jq

# Programming language examples (use quotes for spaces)
claude-tools documentation command "python/reverse list"
claude-tools documentation command "javascript/sort array"
claude-tools documentation command "go/http server"

# Search examples
claude-tools documentation command "~docker~compose"
claude-tools documentation command "~tar~extract"
```

**Coverage:**
- 14,664+ topics including CLI commands and programming languages
- Sources: tldr-pages, cheat.sheets, StackOverflow, Learn X in Y

### api

Get REST API specifications via APIs.guru

```bash
api <api-name|--list> [spec|info]
```

**Examples:**
```bash
# List all available APIs
claude-tools documentation api --list

# Get full OpenAPI spec
claude-tools documentation api stripe.com
claude-tools documentation api github.com
claude-tools documentation api twitter.com

# Get just API info (lighter weight)
claude-tools documentation api github.com info
```

**Output:**
- Returns OpenAPI/Swagger specifications in JSON format
- Use `info` for metadata only (version, description, contact)
- Use `spec` (default) for full API specification

### config

Configure API keys for documentation services

```bash
config <service> [key]
```

**Services:**
- `context7` - Required for `library` command

**Examples:**
```bash
# Set Context7 API key
claude-tools documentation config context7 'ctx7sk-your-key'

# Check if key is set
claude-tools documentation config context7
```

**Setup:**
1. Get free API key at https://context7.com/dashboard
2. Run config command to save to shell profile (~/.zshrc or ~/.bashrc)
3. Restart terminal or run `source ~/.zshrc`

## Use Cases

### For AI Agents

The documentation tool solves the training data cutoff problem by providing:

1. **Current library documentation** - Version-specific docs for libraries updated after training cutoff
2. **Concise command examples** - Token-efficient alternatives to man pages
3. **API specifications** - Up-to-date REST API specs for integration work

**Example workflow:**
```bash
# User asks: "How do I use server actions in Next.js 15?"
# Agent queries current docs
claude-tools documentation library vercel/next.js --topic "server actions" --version v15

# User asks: "How to extract tar files?"
# Agent gets concise examples
claude-tools documentation command tar

# User asks: "What endpoints does the Stripe API have?"
# Agent fetches OpenAPI spec
claude-tools documentation api stripe.com
```

### For Developers

Quick terminal access to:
- Library documentation without opening browser
- CLI command reminders without scrolling man pages
- API specs for integration work

## Key Principles

1. **Unified interface** - One tool for all external documentation needs
2. **Source-appropriate** - Uses the best service for each type (Context7 for libraries, cheat.sh for commands, APIs.guru for REST APIs)
3. **AI-optimized** - Token-efficient responses suitable for context windows
4. **No auth needed** - Only Context7 (library docs) requires API key, command and api work without authentication
5. **Topic filtering** - Get only relevant snippets, not entire documentation dumps

## Comparison with Alternatives

### Library Documentation

| Approach | Pros | Cons |
|----------|------|------|
| **Context7 API** | ✅ Topic filtering<br>✅ Version-specific<br>✅ AI-optimized | 🟡 Requires API key |
| **npm Registry** | ✅ No auth | ❌ README often incomplete<br>❌ No topic filtering |
| **GitHub Raw** | ✅ No auth | ❌ Unstructured markdown<br>❌ Need exact URLs |

### Command Examples

| Approach | Pros | Cons |
|----------|------|------|
| **cheat.sh** | ✅ Curated examples<br>✅ Multi-source<br>✅ No auth | 🟡 Web dependency |
| **man pages** | ✅ Offline<br>✅ Comprehensive | ❌ Verbose (~45k tokens)<br>❌ CLI tools only |
| **tldr-pages** | ✅ Concise | ❌ Requires local install<br>❌ CLI tools only |

### API Specifications

| Approach | Pros | Cons |
|----------|------|------|
| **APIs.guru** | ✅ Centralized<br>✅ OpenAPI format<br>✅ No auth | 🟡 Limited to public APIs |
| **Direct API docs** | ✅ Most current | ❌ Inconsistent formats<br>❌ Need URLs for each |

## Troubleshooting

### "No Context7 API key set"
```bash
# Set your API key
claude-tools documentation config context7 'your-key'

# Or check if already set
claude-tools documentation config context7
```

### Command not found
```bash
# Try different search terms
claude-tools documentation command "~keyword"

# cheat.sh may not have every command
```

### API not found
```bash
# List available APIs
claude-tools documentation api --list

# API names use domain format: github.com, stripe.com, etc.
```

### Rate limits (Context7)
- Free tier has rate limits
- Upgrade at https://context7.com/dashboard

## Resources

- **Context7**: https://context7.com/dashboard
- **cheat.sh**: https://cht.sh/:help
- **APIs.guru**: https://apis.guru/browse-apis/
