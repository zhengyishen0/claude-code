#!/usr/bin/env node
// wait.js - Wait for element or page load

const { getBrowser } = require('./browser');

async function wait(selector, options = {}) {
  let browser;
  try {
    const result = await getBrowser();
    browser = result.browser;
    const page = result.page;

    if (selector) {
      if (options.gone) {
        // Wait for element to disappear
        await page.waitForSelector(selector, { state: 'hidden', timeout: 10000 });
        console.log(`OK: ${selector} disappeared`);
      } else {
        // Wait for element to appear
        await page.waitForSelector(selector, { state: 'visible', timeout: 10000 });
        console.log(`OK: ${selector} found`);
      }
    } else {
      // Wait for page load
      await page.waitForLoadState('domcontentloaded', { timeout: 10000 });
      console.log('OK: Page loaded');
    }

    await browser.close();
  } catch (error) {
    console.error(`TIMEOUT: ${error.message}`);
    if (browser) await browser.close();
    process.exit(1);
  }
}

// Parse arguments
const args = process.argv.slice(2);
let selector = null;
let gone = false;

for (let i = 0; i < args.length; i++) {
  if (args[i] === '--gone') {
    gone = true;
  } else if (!selector) {
    selector = args[i];
  }
}

wait(selector, { gone });
