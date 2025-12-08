#!/usr/bin/env node
// close.js - Close browser and cleanup

const { getBrowser, CONTEXT_DIR } = require('./browser');
const fs = require('fs');
const path = require('path');

async function close() {
  try {
    const { context } = await getBrowser();

    await context.close();

    // Clean up CDP endpoint file
    const cdpFile = path.join(CONTEXT_DIR, 'cdp-endpoint.txt');
    if (fs.existsSync(cdpFile)) {
      fs.unlinkSync(cdpFile);
    }

    console.log('Browser closed');
  } catch (error) {
    console.error(`FAIL: ${error.message}`);
    process.exit(1);
  }
}

close();
