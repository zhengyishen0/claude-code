#!/usr/bin/env node
/**
 * playwright-cli - Chrome automation via Playwright (chrome-cli compatible API)
 *
 * Simple model: Each command starts browser, executes, saves state, closes
 * Profile persistence via storageState files
 * Limitation: Command chaining within same script doesn't share browser state
 */

const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

// Commands
async function cmdOpen(args) {
  const url = args[0];
  if (!url) {
    console.error('Error: URL required');
    process.exit(1);
  }

  const { browser, context } = await getBrowser();
  const page = await context.newPage();
  await page.goto(url, { waitUntil: 'domcontentloaded' });
  await closeBrowser(browser, context);
}

async function cmdExecute(args) {
  const jsCode = args.join(' ');
  if (!jsCode) {
    console.error('Error: JavaScript code required');
    process.exit(1);
  }

  const { browser, context } = await getBrowser();
  const pages = context.pages();

  if (pages.length === 0) {
    const page = await context.newPage();
    pages.push(page);
  }

  const page = pages[pages.length - 1];

  try {
    const result = await page.evaluate((code) => eval(code), jsCode);
    if (result !== undefined && result !== null) {
      if (typeof result === 'string') {
        console.log(result);
      } else {
        console.log(JSON.stringify(result));
      }
    }
  } catch (error) {
    console.error(`Error: ${error.message}`);
    await closeBrowser(browser, context);
    process.exit(1);
  }

  await closeBrowser(browser, context);
}

async function cmdHelp() {
  console.log(`playwright-cli - Chrome automation via Playwright

Usage:
  playwright-cli open <url>              Open URL
  playwright-cli execute <javascript>    Execute JavaScript
  playwright-cli help                    Show this help

Environment Variables:
  PLAYWRIGHT_HEADLESS=false              Run in headed mode (default: true)
  PLAYWRIGHT_PROFILE=/path/to/profile    Use persistent profile

Profile Persistence:
  Cookies and localStorage saved to <profile>/state.json
  Enables persistent login sessions

Limitations:
  Each command starts a fresh browser (profiles still persist via state files)
  For complex command chaining, use headed mode (chrome-cli)

Examples:
  # Headless with profile
  PLAYWRIGHT_PROFILE=~/.claude/profiles/ai-agent playwright-cli open https://gmail.com

  # Headed mode for development
  PLAYWRIGHT_HEADLESS=false playwright-cli open https://example.com
`);
}

// Browser management
async function getBrowser() {
  const headless = process.env.PLAYWRIGHT_HEADLESS !== 'false';
  const profilePath = process.env.PLAYWRIGHT_PROFILE;

  const browser = await chromium.launch({ headless });

  const stateFile = profilePath ? path.join(profilePath, 'state.json') : null;
  const context = await browser.newContext({
    viewport: { width: 1280, height: 720 },
    storageState: stateFile && fs.existsSync(stateFile) ? stateFile : undefined
  });

  return { browser, context };
}

async function closeBrowser(browser, context) {
  const profilePath = process.env.PLAYWRIGHT_PROFILE;

  if (profilePath && context) {
    try {
      const stateFile = path.join(profilePath, 'state.json');
      const state = await context.storageState();
      if (!fs.existsSync(profilePath)) {
        fs.mkdirSync(profilePath, { recursive: true });
      }
      fs.writeFileSync(stateFile, JSON.stringify(state, null, 2));
    } catch (e) {
      console.error(`Warning: Could not save state: ${e.message}`);
    }
  }

  await browser.close();
}

// Main
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
