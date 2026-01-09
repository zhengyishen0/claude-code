# Documentation Tool Reference

Get external documentation for libraries, commands, and APIs.

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
Get library/package documentation via Context7 API.

```bash
library <library-id> [--topic <topic>] [--version <version>] [--format txt|json]
```

**Examples:**
```bash
claude-tools documentation library vercel/next.js --topic routing
claude-tools documentation library reactjs/react.dev --topic hooks
claude-tools documentation library vercel/next.js --version v15.1.8 --topic "server actions"
```

**Finding library IDs:** Visit https://context7.com/dashboard - format is `owner/repo`

### command
Get CLI command examples via cheat.sh.

```bash
command <command-name>
```

**Examples:**
```bash
claude-tools documentation command tar
claude-tools documentation command docker
claude-tools documentation command "python/reverse list"
claude-tools documentation command "~docker~compose"  # Search
```

### api
Get REST API specifications via APIs.guru.

```bash
api <api-name|--list> [spec|info]
```

**Examples:**
```bash
claude-tools documentation api --list
claude-tools documentation api stripe.com
claude-tools documentation api github.com info
```

### config
Configure API keys.

```bash
claude-tools documentation config context7 'ctx7sk-your-key'
```

Get free API key at https://context7.com/dashboard

## Resources

- **Context7**: https://context7.com/dashboard
- **cheat.sh**: https://cht.sh/:help
- **APIs.guru**: https://apis.guru/browse-apis/
