#!/usr/bin/env node
// open.js - Open URL in browser

const { getBrowser } = require('./browser');

async function open(url) {
  let browser;
  try {
    const result = await getBrowser();
    browser = result.browser;
    const page = result.page;

    console.log(`Opening: ${url}`);
    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30000 });

    // Wait for page to stabilize
    await page.waitForLoadState('networkidle', { timeout: 10000 }).catch(() => {
      // Ignore timeout - some pages never reach networkidle
    });

    console.log(`OK: ${page.url()}`);

    // Close connection (browser stays running)
    await browser.close();
  } catch (error) {
    console.error(`FAIL: ${error.message}`);
    if (browser) await browser.close();
    process.exit(1);
  }
}

const url = process.argv[2];
if (!url) {
  console.error('Usage: open <url>');
  process.exit(1);
}

open(url);
