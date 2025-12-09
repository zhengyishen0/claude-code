# Playwright CLI Tool

Cross-platform browser automation with Playwright, wrapped in a shell-friendly CLI similar to the chrome tool.

## Features

- ✅ **Cross-platform** - Works on macOS, Linux, Windows
- ✅ **Multi-browser** - Chrome, Firefox, WebKit support
- ✅ **Shell-friendly** - Simple command-line interface
- ✅ **Chain commands** - Combine multiple actions with `+`
- ✅ **Accessibility tree** - Structured page analysis via `recon`
- ✅ **Auto-waiting** - Built-in element waiting

## Installation

```bash
cd tools/playwright
npm install
npx playwright install chromium
```

## Commands

### open
Open URL in browser

```bash
./run.sh open "https://example.com"
```

### recon
Analyze page structure using accessibility tree

```bash
./run.sh recon
./run.sh recon --full  # Show full tree
```

### click
Click element by selector

```bash
./run.sh click "button#submit"
./run.sh click "[data-testid='login-btn']"
```

### input
Type text into element

```bash
./run.sh input "#email" "test@example.com"
./run.sh input "[name='password']" "secret123"
```

### wait
Wait for element or page load

```bash
./run.sh wait                    # Wait for page load
./run.sh wait "button"           # Wait for element
./run.sh wait "#modal" --gone    # Wait for element to disappear
```

### close
Close browser and cleanup

```bash
./run.sh close
```

## Command Chaining

Combine multiple commands with `+`:

```bash
./run.sh click "button" + wait "#result" + recon
./run.sh input "#search" "playwright" + click "button[type='submit']" + wait
```

## Usage Patterns

### Pattern 1: Single Command per Invocation

Each command launches browser, performs action, and exits:

```bash
./run.sh open "https://example.com"
./run.sh click "a[href='/about']"
./run.sh recon
```

**Pros**: Simple, clean process management
**Cons**: Slower (browser restart overhead)

### Pattern 2: Command Chaining

Chain multiple commands in one invocation:

```bash
./run.sh open "https://example.com" + wait "h1" + recon + click "a" + wait
```

**Pros**: Faster, maintains state
**Cons**: More complex error handling

### Pattern 3: Scripting

Use in shell scripts:

```bash
#!/bin/bash
TOOL="./tools/playwright/run.sh"

$TOOL open "https://example.com"
$TOOL wait "h1"
$TOOL click "button#accept"
$TOOL recon | grep "Success"
```

## Examples

### Example 1: Navigate and Search

```bash
./run.sh open "https://www.google.com" + \\
  wait "[name='q']" + \\
  input "[name='q']" "playwright" + \\
  click "[name='btnK']" + \\
  wait "#search" + \\
  recon
```

### Example 2: Form Automation

```bash
./run.sh open "https://example.com/login" + \\
  input "#username" "user@example.com" + \\
  input "#password" "secret" + \\
  click "button[type='submit']" + \\
  wait ".dashboard"
```

### Example 3: Data Extraction

```bash
./run.sh open "https://example.com/products" + \\
  wait "[data-product]" + \\
  recon | grep -A 2 "## Interactive Elements"
```

## Architecture

### Browser State Management

The tool uses Playwright's persistent context to maintain browser state:

- **First run**: Launches new browser with `launchPersistentContext`
- **Subsequent runs**: Connects via CDP (Chrome DevTools Protocol)
- **State directory**: `~/.playwright-cli` (configurable via `PLAYWRIGHT_CONTEXT_DIR`)

### File Structure

```
tools/playwright/
├── run.sh              # Main entry point
├── package.json        # Dependencies
├── js/
│   ├── browser.js      # Browser state manager
│   ├── open.js         # Open URL command
│   ├── click.js        # Click command
│   ├── input.js        # Input command
│   ├── wait.js         # Wait command
│   ├── recon.js        # Recon command
│   └── close.js        # Close command
└── README.md           # This file
```

## Environment Variables

- `PLAYWRIGHT_CONTEXT_DIR` - Browser state directory (default: `~/.playwright-cli`)
- `NODE` - Node.js binary path (default: `node`)

## Comparison with Chrome Tool

| Feature | Chrome Tool | Playwright Tool |
|---------|-------------|-----------------|
| **Platform** | macOS only | Cross-platform |
| **Browser** | Chrome only | Chrome, Firefox, WebKit |
| **Dependency** | chrome-cli (brew) | Node.js + Playwright |
| **Auto-wait** | Manual | Built-in |
| **Recon** | HTML to Markdown | Accessibility tree |
| **State** | Via chrome-cli | Persistent context + CDP |

## Troubleshooting

### Browser won't close

```bash
# Kill manually
pkill -f "Google Chrome for Testing"

# Clean up state
rm -rf ~/.playwright-cli
```

### Connection errors

```bash
# Reset everything
./run.sh close
rm -rf ~/.playwright-cli
```

### Permission denied

```bash
chmod +x run.sh
```

## Advanced Usage

### Custom Browser Options

Edit `js/browser.js` to customize browser launch options:

```javascript
const context = await chromium.launchPersistentContext(CONTEXT_DIR, {
  headless: true,          // Run headless
  viewport: { width: 1920, height: 1080 },
  locale: 'en-US',
  timezoneId: 'America/New_York'
});
```

### Headless Mode

For CI/CD or background automation, enable headless mode in `browser.js`:

```javascript
headless: true
```

### Firefox or WebKit

Change `chromium` to `firefox` or `webkit` in `js/browser.js`:

```javascript
const { firefox } = require('playwright');
const context = await firefox.launchPersistentContext(...);
```

## Known Limitations

1. **State persistence** - Browser state may not persist perfectly between separate command invocations
2. **Process cleanup** - Node processes may not exit cleanly in some scenarios
3. **Single browser instance** - Only one browser instance supported at a time

## Roadmap

- [ ] MCP server mode for AI agent integration
- [ ] Better state persistence between commands
- [ ] Screenshot and PDF generation commands
- [ ] Network interception and mocking
- [ ] Mobile device emulation
- [ ] Multi-browser support (run Firefox and Chrome simultaneously)

## Contributing

This tool follows the design principles outlined in `/CLAUDE.md`:

1. **Self-documenting** - `run.sh` with no args shows help
2. **Single entry point** - All commands via `run.sh`
3. **JavaScript in js/** - Separate JS from shell scripts
4. **Standard structure** - Matches other tools in `tools/`

## License

MIT
