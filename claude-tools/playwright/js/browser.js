// browser.js - Browser state manager for persistent Playwright context
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');
const os = require('os');

const CONTEXT_DIR = process.env.PLAYWRIGHT_CONTEXT_DIR || path.join(os.homedir(), '.playwright-cli');
const STATE_FILE = path.join(CONTEXT_DIR, 'state.json');
const CDP_FILE = path.join(CONTEXT_DIR, 'cdp-endpoint.txt');

// Ensure context directory exists
if (!fs.existsSync(CONTEXT_DIR)) {
  fs.mkdirSync(CONTEXT_DIR, { recursive: true });
}

/**
 * Get or create a persistent browser context
 * @returns {Promise<{browser: Browser, context: BrowserContext, page: Page}>}
 */
async function getOrCreateContext() {
  try {
    // First, try to connect to existing browser via CDP
    if (fs.existsSync(CDP_FILE)) {
      const cdpEndpoint = fs.readFileSync(CDP_FILE, 'utf-8').trim();
      try {
        const browser = await chromium.connectOverCDP(cdpEndpoint);
        const contexts = browser.contexts();

        if (contexts.length > 0) {
          const context = contexts[0];
          const pages = context.pages();
          const page = pages.length > 0 ? pages[0] : await context.newPage();

          return { browser, context, page };
        }
      } catch (error) {
        // Connection failed, clean up stale file
        fs.unlinkSync(CDP_FILE);
      }
    }

    // Launch new persistent context with CDP enabled
    const context = await chromium.launchPersistentContext(CONTEXT_DIR, {
      headless: false,
      viewport: { width: 1280, height: 800 },
      args: [
        '--disable-blink-features=AutomationControlled',
        '--remote-debugging-port=9222'
      ]
    });

    // Get the browser from context
    const browser = context.browser();

    // Get or create a page
    let pages = context.pages();
    let page;

    if (pages.length === 0) {
      page = await context.newPage();
    } else {
      page = pages[0];
    }

    // Save CDP endpoint for future connections
    const cdpEndpoint = 'http://localhost:9222';
    fs.writeFileSync(CDP_FILE, cdpEndpoint);
    saveState({ initialized: true, timestamp: Date.now() });

    // For first launch, return the browser object (even though it's null for persistent context)
    // We'll use a fake browser object that when closed, does nothing
    const fakeBrowser = {
      close: async () => {
        // Do nothing - context stays open
      },
      contexts: () => [context]
    };

    return { browser: fakeBrowser, context, page };
  } catch (error) {
    console.error('Failed to create browser context:', error.message);
    throw error;
  }
}

/**
 * Connect to existing browser or create new one
 * @returns {Promise<{browser: Browser, context: BrowserContext, page: Page, shouldClose: boolean}>}
 */
async function getBrowser() {
  return await getOrCreateContext();
}

/**
 * Save state to file
 */
function saveState(state) {
  try {
    fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 2));
  } catch (error) {
    // Ignore write errors
  }
}

/**
 * Load state from file
 */
function loadState() {
  try {
    if (fs.existsSync(STATE_FILE)) {
      return JSON.parse(fs.readFileSync(STATE_FILE, 'utf-8'));
    }
  } catch (error) {
    // Ignore read errors
  }
  return {};
}

/**
 * Close browser and cleanup
 */
async function closeBrowser() {
  try {
    const context = await chromium.launchPersistentContext(CONTEXT_DIR, { headless: false });
    await context.close();

    // Clean up state
    if (fs.existsSync(STATE_FILE)) {
      fs.unlinkSync(STATE_FILE);
    }

    console.log('Browser closed');
  } catch (error) {
    console.error('Failed to close browser:', error.message);
    throw error;
  }
}

module.exports = {
  getBrowser,
  closeBrowser,
  CONTEXT_DIR
};
