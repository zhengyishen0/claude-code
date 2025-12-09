#!/usr/bin/env node
// input.js - Type text into element

const { getBrowser } = require('./browser');

async function input(selector, value) {
  let browser;
  try {
    const result = await getBrowser();
    browser = result.browser;
    const page = result.page;

    // Clear existing value and type new one
    await page.fill(selector, value, { timeout: 5000 });

    console.log(`OK: Set ${selector} = "${value}"`);

    await browser.close();
  } catch (error) {
    console.error(`FAIL: ${error.message}`);
    if (browser) await browser.close();
    process.exit(1);
  }
}

const selector = process.argv[2];
const value = process.argv[3];

if (!selector || !value) {
  console.error('Usage: input <selector> <value>');
  process.exit(1);
}

input(selector, value);
