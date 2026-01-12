#!/usr/bin/env node
/**
 * cdp-cli - Minimal CDP interface for Chrome automation
 *
 * Provides ONLY open and execute - all other functionality
 * is handled by existing chrome tool commands via execute
 */

const CDP = require('chrome-remote-interface');

const CDP_PORT = parseInt(process.env.CDP_PORT || '9222', 10);
const CDP_HOST = process.env.CDP_HOST || 'localhost';

async function connectCDP() {
  try {
    const client = await CDP({ port: CDP_PORT, host: CDP_HOST });
    return client;
  } catch (error) {
    console.error(`Failed to connect to Chrome CDP on ${CDP_HOST}:${CDP_PORT}`);
    console.error('Make sure Chrome is running with --remote-debugging-port flag');
    console.error(`Error: ${error.message}`);
    process.exit(1);
  }
}

async function cmdOpen(args) {
  const url = args[0];
  if (!url) {
    console.error('Error: URL required');
    process.exit(1);
  }

  const client = await connectCDP();
  const { Page } = client;

  try {
    await Page.enable();
    await Page.navigate({ url });
    await Page.loadEventFired();
    await client.close();
  } catch (error) {
    console.error(`Error: ${error.message}`);
    await client.close();
    process.exit(1);
  }
}

async function cmdExecute(args) {
  // Take first arg as-is (preserves newlines when passed via shell)
  const jsCode = args[0] || '';
  if (!jsCode) {
    console.error('Error: JavaScript code required');
    process.exit(1);
  }

  const client = await connectCDP();
  const { Runtime } = client;

  try {
    await Runtime.enable();

    const result = await Runtime.evaluate({
      expression: jsCode,
      returnByValue: true,
      awaitPromise: true
    });

    if (result.exceptionDetails) {
      console.error(`Error: ${result.exceptionDetails.text}`);
      if (result.exceptionDetails.exception) {
        console.error(`Exception: ${JSON.stringify(result.exceptionDetails.exception, null, 2)}`);
      }
      console.error(`Line: ${result.exceptionDetails.lineNumber}, Column: ${result.exceptionDetails.columnNumber}`);
      await client.close();
      process.exit(1);
    }

    if (result.result.value !== undefined && result.result.value !== null) {
      if (typeof result.result.value === 'string') {
        console.log(result.result.value);
      } else {
        console.log(JSON.stringify(result.result.value));
      }
    }

    await client.close();
  } catch (error) {
    console.error(`Error: ${error.message}`);
    await client.close();
    process.exit(1);
  }
}

async function cmdScreenshot(args) {
  const fullPage = args.includes('--full');
  const format = args.includes('--png') ? 'png' : 'jpeg';
  const quality = parseInt(args.find(arg => arg.startsWith('--quality='))?.split('=')[1] || '70', 10);
  const width = parseInt(args.find(arg => arg.startsWith('--width='))?.split('=')[1] || '1200', 10);
  const height = parseInt(args.find(arg => arg.startsWith('--height='))?.split('=')[1] || '800', 10);
  const noResize = args.includes('--no-resize');

  // Auto-generate output path
  const timestamp = new Date().toISOString().replace(/[:.]/g, '-').split('T').join('-').slice(0, -5);
  const outputPath = `/tmp/screenshot-${timestamp}.${format === 'png' ? 'png' : 'jpg'}`;

  const client = await connectCDP();
  const { Page, Emulation } = client;

  try {
    await Page.enable();

    // Set optimal viewport for token efficiency (unless --no-resize or --full)
    if (!noResize && !fullPage) {
      await Emulation.setDeviceMetricsOverride({
        width,
        height,
        deviceScaleFactor: 1,
        mobile: false
      });
    }

    const screenshotOptions = {
      format,
      captureBeyondViewport: fullPage,
      fromSurface: true
    };

    if (format === 'jpeg') {
      screenshotOptions.quality = quality;
    }

    const result = await Page.captureScreenshot(screenshotOptions);

    // Write base64 data to file
    const fs = require('fs');
    const buffer = Buffer.from(result.data, 'base64');
    fs.writeFileSync(outputPath, buffer);

    // Output path with instruction for LLMs
    console.log(`Screenshot saved: ${outputPath}`);
    console.log('Use Read tool to view the image.');

    await client.close();
  } catch (error) {
    console.error(`Error: ${error.message}`);
    await client.close();
    process.exit(1);
  }
}

async function cmdClick(args) {
  const x = parseInt(args[0], 10);
  const y = parseInt(args[1], 10);

  if (isNaN(x) || isNaN(y)) {
    console.error('Error: X and Y coordinates required');
    console.error('Usage: cdp-cli click <x> <y>');
    process.exit(1);
  }

  const client = await connectCDP();
  const { Input } = client;

  try {
    // Mouse press
    await Input.dispatchMouseEvent({
      type: 'mousePressed',
      x,
      y,
      button: 'left',
      clickCount: 1
    });

    // Mouse release
    await Input.dispatchMouseEvent({
      type: 'mouseReleased',
      x,
      y,
      button: 'left',
      clickCount: 1
    });

    console.log(`✓ Clicked at (${x}, ${y})`);

    await client.close();
  } catch (error) {
    console.error(`Error: ${error.message}`);
    await client.close();
    process.exit(1);
  }
}

async function cmdHover(args) {
  const x = parseInt(args[0], 10);
  const y = parseInt(args[1], 10);

  if (isNaN(x) || isNaN(y)) {
    console.error('Error: X and Y coordinates required');
    console.error('Usage: cdp-cli hover <x> <y>');
    process.exit(1);
  }

  const client = await connectCDP();
  const { Input } = client;

  try {
    await Input.dispatchMouseEvent({
      type: 'mouseMoved',
      x,
      y
    });

    console.log(`✓ Hover at (${x}, ${y})`);

    await client.close();
  } catch (error) {
    console.error(`Error: ${error.message}`);
    await client.close();
    process.exit(1);
  }
}

async function cmdDrag(args) {
  const x1 = parseInt(args[0], 10);
  const y1 = parseInt(args[1], 10);
  const x2 = parseInt(args[2], 10);
  const y2 = parseInt(args[3], 10);

  if (isNaN(x1) || isNaN(y1) || isNaN(x2) || isNaN(y2)) {
    console.error('Error: Start and end coordinates required');
    console.error('Usage: cdp-cli drag <x1> <y1> <x2> <y2>');
    process.exit(1);
  }

  const client = await connectCDP();
  const { Input } = client;

  try {
    // Mouse press at start
    await Input.dispatchMouseEvent({
      type: 'mousePressed',
      x: x1,
      y: y1,
      button: 'left',
      clickCount: 1
    });

    // Move to end (with button held)
    await Input.dispatchMouseEvent({
      type: 'mouseMoved',
      x: x2,
      y: y2,
      button: 'left'
    });

    // Release at end
    await Input.dispatchMouseEvent({
      type: 'mouseReleased',
      x: x2,
      y: y2,
      button: 'left',
      clickCount: 1
    });

    console.log(`✓ Dragged from (${x1}, ${y1}) to (${x2}, ${y2})`);

    await client.close();
  } catch (error) {
    console.error(`Error: ${error.message}`);
    await client.close();
    process.exit(1);
  }
}

function cmdHelp() {
  console.log(`cdp-cli - Minimal CDP interface for Chrome

Usage:
  cdp-cli open <url>                        Open URL
  cdp-cli execute <javascript>              Execute JavaScript
  cdp-cli screenshot [options]              Capture screenshot (VISUAL)
  cdp-cli click <x> <y>                     Click at coordinates (VISUAL)
  cdp-cli hover <x> <y>                     Hover at coordinates (VISUAL)
  cdp-cli drag <x1> <y1> <x2> <y2>          Drag from->to (VISUAL)
  cdp-cli help                              Show this help

Environment Variables:
  CDP_PORT=9222                   CDP port (default: 9222)
  CDP_HOST=localhost              CDP host (default: localhost)

Prerequisites:
  Chrome must be running with CDP enabled

=== Core Commands ===

  # Open page
  cdp-cli open https://example.com

  # Execute JavaScript
  cdp-cli execute "document.title"

  # Execute with result
  cdp-cli execute "document.querySelector('h1').innerText"

=== Visual Commands ===

Visual commands use coordinates from screenshots for vision-based automation.
No CSS selectors needed!

  # Take screenshot (auto-generates path, optimized: 1200x800, ~1,280 tokens)
  cdp-cli screenshot
  # Output: /tmp/screenshot-2025-12-27-12-34-56.jpg

  # Click at coordinates (from screenshot)
  cdp-cli click 237 267

  # Hover at coordinates
  cdp-cli hover 400 300

  # Drag from one point to another
  cdp-cli drag 100 200 300 400

Screenshot Options:
  --width=N         Viewport width (default: 1200)
  --height=N        Viewport height (default: 800)
  --quality=N       JPEG quality 1-100 (default: 70)
  --full            Capture full page (disables resize)
  --png             PNG format instead of JPEG
  --no-resize       Skip viewport resize, use current size

Vision Token Cost (pixels/750):
  1200x800:        ~1,280 tokens ⭐ (recommended)
  1504x817:        ~1,638 tokens
  800x600:         ~640 tokens
  1568x1568:       ~3,281 tokens (max before auto-resize)

Vision Workflow:
  1. screenshot → Auto-generates path, outputs location
  2. AI uses Read tool → Views and analyzes image
  3. AI identifies coordinates → Provides element locations
  4. click/hover/drag → Interact using coordinates
  No CSS selectors needed!

Example workflow:
  $ cdp-cli screenshot
  Screenshot saved: /tmp/screenshot-2025-12-27-12-34-56.jpg
  Use Read tool to view the image.

  [AI uses Read tool, analyzes image and says: "Search button is at (600, 130)"]

  $ cdp-cli click 600 130
  ✓ Clicked at (600, 130)

Note:
  This is a minimal interface. All higher-level commands (click, wait,
  input, etc.) are handled by the chrome tool via execute.
`);
}

async function main() {
  const args = process.argv.slice(2);

  if (args.length === 0) {
    cmdHelp();
    return;
  }

  const command = args[0];
  const commandArgs = args.slice(1);

  try {
    switch (command) {
      case 'open':
        await cmdOpen(commandArgs);
        break;
      case 'execute':
        await cmdExecute(commandArgs);
        break;
      case 'screenshot':
        await cmdScreenshot(commandArgs);
        break;
      case 'click':
        await cmdClick(commandArgs);
        break;
      case 'hover':
        await cmdHover(commandArgs);
        break;
      case 'drag':
        await cmdDrag(commandArgs);
        break;
      case 'help':
      case '--help':
      case '-h':
        cmdHelp();
        break;
      default:
        console.error(`Unknown command: ${command}`);
        process.exit(1);
    }
  } catch (error) {
    console.error(`Fatal error: ${error.message}`);
    process.exit(1);
  }
}

main();
