# Context7 Tool

Fetch up-to-date library documentation via Context7 API

## Quick Start

```bash
# Set your API key (get one at https://context7.com/dashboard)
export CONTEXT7_API_KEY='your-api-key'

# Search for a library
claude-tools context7 search "next.js"

# Get documentation
claude-tools context7 docs vercel/next.js --topic routing
```

## Commands

### search
Search for libraries in the Context7 database

```bash
search <query>
```

**Examples:**
```bash
claude-tools context7 search react
claude-tools context7 search "tanstack query"
claude-tools context7 search express
```

**Output:**
Returns a list of matching libraries with:
- Library ID (use this for the `docs` command)
- Title and description
- Star count
- Number of snippets available
- Trust score

### docs
Get documentation for a specific library

```bash
docs <library-id> [--topic <topic>] [--version <version>] [--format txt|json]
```

**Options:**
- `--topic <topic>` - Filter documentation by topic (e.g., 'routing', 'hooks', 'middleware')
- `--version <version>` - Get documentation for a specific version
- `--format txt|json` - Output format (default: txt for human reading, json for parsing)

**Examples:**
```bash
# Get Next.js routing documentation
claude-tools context7 docs vercel/next.js --topic routing

# Get React hooks documentation
claude-tools context7 docs reactjs/react.dev --topic hooks

# Get Express middleware examples
claude-tools context7 docs expressjs/express --topic middleware

# Get specific version documentation
claude-tools context7 docs vercel/next.js --version v15.1.8 --topic "server actions"

# Get JSON output for programmatic use
claude-tools context7 docs vercel/next.js --topic routing --format json
```

**Output (txt format):**
Returns curated code snippets with:
- Code title and description
- Executable code examples
- Source links
- Best practices

**Output (json format):**
Returns structured data with:
- Array of snippets
- Each snippet includes: title, description, code, language, source link
- Pagination info
- Total token count

## Setup

### 1. Get API Key
Visit https://context7.com/dashboard to get your free API key.

### 2. Set Environment Variable
```bash
# Add to your ~/.zshrc or ~/.bashrc
export CONTEXT7_API_KEY='ctx7sk-your-key-here'
```

### 3. Verify Setup
```bash
claude-tools context7 search react
```

## Use Cases

### For AI Coding Agents
Context7 solves the training data cutoff problem by providing current, version-specific documentation:

**Problem:** AI agents trained on data from January 2025 might suggest outdated patterns for libraries updated since then.

**Solution:** Query Context7 for current documentation when:
- User asks about version-specific features
- Library might have changed since training cutoff
- Need to verify current best practices
- Working with newly released libraries

**Example workflow:**
```bash
# User asks: "How do I use server actions in Next.js 15?"
# Agent searches for Next.js
claude-tools context7 search "next.js"

# Agent gets current server actions docs
claude-tools context7 docs vercel/next.js --topic "server actions" --version v15

# Agent provides current, correct code patterns
```

### For Developers
Get instant access to curated code examples without leaving the terminal:

```bash
# Quick reference for Express middleware patterns
claude-tools context7 docs expressjs/express --topic middleware

# Learn React 19 hooks
claude-tools context7 docs reactjs/react.dev --topic hooks

# Understand Next.js App Router
claude-tools context7 docs vercel/next.js --topic "app router"
```

## Key Principles

1. **Topic-Based Filtering** - Get only relevant snippets, not entire docs
2. **Version-Specific** - Fetch documentation for exact library versions
3. **AI-Optimized** - Structured code snippets with context, not raw HTML
4. **Curated Examples** - Working code patterns, not just API references
5. **Current Data** - Regularly updated from source repositories

## Comparison with Alternatives

| Approach | Pros | Cons |
|----------|------|------|
| **Context7 API** | ✅ Topic filtering<br>✅ Curated snippets<br>✅ Version-specific<br>✅ AI-optimized | 🟡 Requires API key<br>🟡 Rate limits |
| **npm Registry** | ✅ No auth<br>✅ Free | ❌ README often empty<br>❌ No topic filtering<br>❌ Not AI-optimized |
| **GitHub Raw** | ✅ No auth<br>✅ Free | ❌ Unstructured markdown<br>❌ Need repo URLs<br>❌ No topic filtering |
| **man pages** | ✅ Offline<br>✅ Fast | ❌ Only for CLI tools<br>❌ No npm packages |

## API Response Examples

### Search Response
```json
{
  "results": [
    {
      "id": "/vercel/next.js",
      "title": "Next.js",
      "description": "The React Framework for Production",
      "stars": 125000,
      "totalSnippets": 1520,
      "trustScore": 10
    }
  ]
}
```

### Docs Response (JSON)
```json
{
  "snippets": [
    {
      "codeTitle": "Server Actions in Next.js 15",
      "codeDescription": "Create and use server actions with the 'use server' directive",
      "codeLanguage": "typescript",
      "codeList": [
        {
          "language": "typescript",
          "code": "// app/actions.ts\n'use server'\n\nexport async function createUser(formData: FormData) {\n  const name = formData.get('name')\n  // ... server-side logic\n}"
        }
      ],
      "pageTitle": "Server Actions and Mutations"
    }
  ],
  "totalTokens": 1699,
  "pagination": {
    "page": 1,
    "limit": 10,
    "hasNext": true
  }
}
```

## Tips

**Finding Library IDs:**
1. Use `search` command first to find the correct library ID
2. Library IDs follow the format: `owner/repo` or `/websites/site-name`
3. Multiple sources may exist for popular libraries (choose by trust score)

**Effective Topic Filtering:**
- Use specific terms: "routing" not "routes"
- Try variations: "middleware" vs "middlewares"
- Common topics: hooks, routing, middleware, authentication, state management

**Combining with Claude:**
Claude can automatically use this tool to fetch current documentation when helping you code, ensuring suggestions are based on current APIs rather than training data.

## Troubleshooting

**"API key not set" error:**
```bash
export CONTEXT7_API_KEY='your-key-here'
# Verify:
echo $CONTEXT7_API_KEY
```

**No results for search:**
- Try different search terms
- Check spelling
- Some packages may not be indexed yet

**Rate limit errors:**
- Free tier has limits
- Upgrade at https://context7.com/dashboard
- Or space out requests

## Resources

- Context7 Dashboard: https://context7.com/dashboard
- API Documentation: https://github.com/upstash/context7
- Get Support: https://github.com/upstash/context7/issues
