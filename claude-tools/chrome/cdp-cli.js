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
  const jsCode = args.join(' ');
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

function cmdHelp() {
  console.log(`cdp-cli - Minimal CDP interface for Chrome

Usage:
  cdp-cli open <url>              Open URL
  cdp-cli execute <javascript>    Execute JavaScript
  cdp-cli help                    Show this help

Environment Variables:
  CDP_PORT=9222                   CDP port (default: 9222)
  CDP_HOST=localhost              CDP host (default: localhost)

Prerequisites:
  Chrome must be running with CDP enabled

Examples:
  # Open page
  cdp-cli open https://example.com

  # Execute JavaScript
  cdp-cli execute "document.title"

  # Execute with result
  cdp-cli execute "document.querySelector('h1').innerText"

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
