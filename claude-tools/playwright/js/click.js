#!/usr/bin/env node
// click.js - Click element by selector

const { getBrowser } = require('./browser');

async function click(selector) {
  let browser;
  try {
    const result = await getBrowser();
    browser = result.browser;
    const page = result.page;

    // Wait for element and click
    await page.click(selector, { timeout: 5000 });

    console.log(`OK: Clicked ${selector}`);

    await browser.close();
  } catch (error) {
    console.error(`FAIL: ${error.message}`);
    if (browser) await browser.close();
    process.exit(1);
  }
}

const selector = process.argv[2];
if (!selector) {
  console.error('Usage: click <selector>');
  process.exit(1);
}

click(selector);
