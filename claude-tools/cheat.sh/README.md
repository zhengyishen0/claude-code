# cheat.sh

Get concise CLI command examples via cheat.sh API (no wrapper needed - use curl directly)

## Usage

cheat.sh is a web service providing curated command examples. It aggregates multiple sources including tldr-pages, cheat.sheets, and StackOverflow. Access it directly with curl.

**Basic queries:**
```bash
# CLI commands
curl -s 'cht.sh/tar?T'
curl -s 'cht.sh/git?T'
curl -s 'cht.sh/jq?T'

# Programming languages (use + for spaces)
curl -s 'cht.sh/python/reverse+list?T'
curl -s 'cht.sh/javascript/sort+array?T'
curl -s 'cht.sh/go/http+server?T'
```

**Search:**
```bash
# Search all cheat sheets
curl -s 'cht.sh/~keyword?T'

# Search within language
curl -s 'cht.sh/python/~closure?T'

# Multiple keywords
curl -s 'cht.sh/~tar~extract?T'
```

**Options:**
- `?T` - Text only, no ANSI colors (always use this)
- `?Q` - Code only, no comments
- `?q` - Quiet mode, no github/twitter buttons

**Special queries:**
```bash
# List topics in a language
curl -s 'cht.sh/python/:list?T'

# Learn a language from scratch
curl -s 'cht.sh/python/:learn?T'

# List all available cheat sheets
curl -s 'cht.sh/:list?T'
```

## Key Principles

1. **No wrapper needed** - Direct curl access is simple and sufficient
2. **Always use ?T flag** - Text-only output is easier to parse
3. **No authentication** - Completely open API
4. **Includes tldr content** - Aggregates tldr-pages plus additional sources
5. **14,664 topics** - Covers CLI commands + programming languages
6. **Token efficient** - ~95% reduction vs man pages (~2,000 vs ~45,000 tokens)
7. **For AI agents** - Provides concise, curated examples for context windows

## Coverage

- CLI commands: tar, git, curl, docker, kubectl, etc.
- Programming languages: python, javascript, go, rust, etc.
- Sources: tldr-pages, cheat.sheets, StackOverflow, Learn X in Y

## Examples

```bash
# Get tar examples
curl -s 'cht.sh/tar?T'

# Find how to reverse a list in Python
curl -s 'cht.sh/python/reverse+list?T'

# Search for docker compose examples
curl -s 'cht.sh/~docker~compose?T'

# Get code only (no explanations)
curl -s 'cht.sh/python/http+server?Q'
```

## URL

Base URL: `https://cht.sh/` (or `https://cheat.sh/`)

Full documentation: `curl cht.sh/:help`
