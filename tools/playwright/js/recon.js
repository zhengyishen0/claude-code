#!/usr/bin/env node
// recon.js - Analyze page structure

const { getBrowser } = require('./browser');

async function recon(options = {}) {
  let browser;
  try {
    const result = await getBrowser();
    browser = result.browser;
    const page = result.page;

    const url = page.url();
    const title = await page.title();

    console.log(`# ${title}`);
    console.log(`URL: ${url}\n`);

    // Get page structure using accessibility tree
    const snapshot = await page.accessibility.snapshot();

    if (snapshot) {
      console.log('## Page Structure\n');
      printTree(snapshot, 0, options.full);
    }

    // Get interactive elements
    console.log('\n## Interactive Elements\n');

    const buttons = await page.$$eval('button, [role="button"], a[href]', els =>
      els.slice(0, 20).map((el, i) => ({
        type: el.tagName.toLowerCase(),
        text: el.textContent?.trim().substring(0, 50) || '',
        id: el.id || '',
        class: el.className || '',
        href: el.getAttribute('href') || ''
      }))
    );

    buttons.forEach((btn, i) => {
      const id = btn.id ? `#${btn.id}` : '';
      const cls = btn.class ? `.${btn.class.split(' ')[0]}` : '';
      const selector = id || cls || btn.type;
      const text = btn.text ? ` - ${btn.text}` : '';
      const href = btn.href ? ` -> ${btn.href}` : '';
      console.log(`${i + 1}. [${btn.type}${selector}]${text}${href}`);
    });

    // Get form inputs
    const inputs = await page.$$eval('input, textarea, select', els =>
      els.slice(0, 10).map((el, i) => ({
        type: el.type || el.tagName.toLowerCase(),
        name: el.name || '',
        id: el.id || '',
        placeholder: el.placeholder || '',
        value: el.value || ''
      }))
    );

    if (inputs.length > 0) {
      console.log('\n## Form Inputs\n');
      inputs.forEach((input, i) => {
        const id = input.id ? `#${input.id}` : '';
        const name = input.name ? `[name="${input.name}"]` : '';
        const selector = id || name || input.type;
        const placeholder = input.placeholder ? ` (${input.placeholder})` : '';
        console.log(`${i + 1}. ${input.type}${selector}${placeholder}`);
      });
    }

    await browser.close();
  } catch (error) {
    console.error(`FAIL: ${error.message}`);
    if (browser) await browser.close();
    process.exit(1);
  }
}

function printTree(node, depth, full = false) {
  if (!node) return;

  const indent = '  '.repeat(depth);

  // Print node info
  if (node.name) {
    const role = node.role || '';
    const name = node.name.substring(0, 100);
    console.log(`${indent}- ${role}: ${name}`);
  }

  // Print children (limit depth if not full mode)
  if (node.children && (full || depth < 3)) {
    node.children.forEach(child => printTree(child, depth + 1, full));
  }
}

// Parse arguments
const args = process.argv.slice(2);
const full = args.includes('--full');

recon({ full });
