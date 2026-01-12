#!/usr/bin/env node
/**
 * browser - Browser automation with CDP (Chrome DevTools Protocol)
 * Pure Node.js implementation replacing run.sh + cdp-cli.js + Python scripts
 */

const CDP = require('chrome-remote-interface');
const { spawn, execSync, spawnSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const http = require('http');
const { createHash } = require('crypto');
const readline = require('readline');

// ============================================================================
// Configuration
// ============================================================================

const SCRIPT_DIR = __dirname;
const TOOL_NAME = path.basename(SCRIPT_DIR);
const CHROME_APP = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

// Directories
const DATA_DIR = path.join(SCRIPT_DIR, 'data');
const PROFILES_DIR = path.join(SCRIPT_DIR, 'profiles');
const DEFAULT_PROFILE = path.join(DATA_DIR, 'default');
const SNAPSHOT_DIR = '/tmp/chrome-snapshots';
const PORT_REGISTRY = path.join(DATA_DIR, 'port-registry');

// CDP settings (can be overridden by profile)
let CDP_PORT = parseInt(process.env.CDP_PORT || '9222', 10);
let CDP_HOST = process.env.CDP_HOST || 'localhost';

// Global flags
let PROFILE = '';
let PROFILE_PATH = '';
let DEBUG_MODE = false;

// Ensure directories exist
fs.mkdirSync(DATA_DIR, { recursive: true });
fs.mkdirSync(PROFILES_DIR, { recursive: true });
fs.mkdirSync(SNAPSHOT_DIR, { recursive: true });

// ============================================================================
// Profile Utilities
// ============================================================================

function normalizeProfileName(name) {
  return name.toLowerCase().replace(/[^a-z0-9]/g, '_').replace(/_+/g, '_');
}

function expandProfilePath(profile) {
  if (profile.startsWith('/') || profile.startsWith('~')) {
    return profile;
  }
  return path.join(PROFILES_DIR, normalizeProfileName(profile));
}

function getServiceName(url) {
  try {
    const domain = new URL(url).hostname;

    // Check domain mappings
    const mappingsFile = path.join(SCRIPT_DIR, 'domain-mappings.json');
    if (fs.existsSync(mappingsFile)) {
      const mappings = JSON.parse(fs.readFileSync(mappingsFile, 'utf8'));
      if (mappings[domain]) {
        return mappings[domain];
      }
    }

    // Fallback: strip TLD
    return domain
      .replace(/^www\./, '')
      .replace(/\.(com|co\.uk|de|ca|fr|jp|org|net|io|app|dev)$/, '')
      .replace(/\./g, '-');
  } catch {
    return 'unknown';
  }
}

function writeProfileMetadata(profilePath, service, account, source, sourceType, sourcePath = '') {
  const metaFile = path.join(profilePath, '.profile-meta.json');
  const now = new Date().toISOString();

  const meta = {
    display: `<${service}> ${account} (${source})`,
    service,
    account,
    source,
    source_type: sourceType,
    source_path: sourcePath,
    created: now,
    last_used: now,
    status: 'enabled'
  };

  fs.writeFileSync(metaFile, JSON.stringify(meta, null, 2));
}

function readProfileMetadata(profilePath, field) {
  const metaFile = path.join(profilePath, '.profile-meta.json');
  if (!fs.existsSync(metaFile)) return null;

  try {
    const meta = JSON.parse(fs.readFileSync(metaFile, 'utf8'));
    return meta[field] || null;
  } catch {
    return null;
  }
}

function updateProfileMetadata(profilePath, field, value) {
  const metaFile = path.join(profilePath, '.profile-meta.json');
  if (!fs.existsSync(metaFile)) return false;

  try {
    const meta = JSON.parse(fs.readFileSync(metaFile, 'utf8'));
    meta[field] = value;
    fs.writeFileSync(metaFile, JSON.stringify(meta, null, 2));
    return true;
  } catch {
    return false;
  }
}

function fuzzyMatchProfile(search) {
  if (!fs.existsSync(PROFILES_DIR)) return [];

  const searchLower = search.toLowerCase();
  const matches = [];

  for (const name of fs.readdirSync(PROFILES_DIR)) {
    const profilePath = path.join(PROFILES_DIR, name);
    if (!fs.statSync(profilePath).isDirectory()) continue;

    if (name.toLowerCase().includes(searchLower)) {
      matches.push(name);
    }
  }

  return matches;
}

// ============================================================================
// Port Registry and Profile Locking
// ============================================================================

function initRegistry() {
  fs.mkdirSync(path.dirname(PORT_REGISTRY), { recursive: true });
  if (!fs.existsSync(PORT_REGISTRY)) {
    fs.writeFileSync(PORT_REGISTRY, '');
  }
}

function getProfilePort(profile) {
  // Hash-based port assignment (9222-9299)
  const hash = createHash('md5').update(profile).digest();
  const num = hash.readUInt32LE(0);
  return 9222 + (num % 78);
}

function isPortInUse(port) {
  try {
    execSync(`lsof -i :${port} -sTCP:LISTEN`, { stdio: 'pipe' });
    return true;
  } catch {
    return false;
  }
}

function isProcessRunning(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

function isProfileInUse(profile) {
  initRegistry();

  const lines = fs.readFileSync(PORT_REGISTRY, 'utf8').split('\n').filter(Boolean);
  const entry = lines.find(line => line.startsWith(`${profile}:`));

  if (!entry) return null;

  const [, port, pid, startTime] = entry.split(':');

  // Verify process is still running
  if (!isProcessRunning(parseInt(pid, 10))) {
    // Stale entry, clean it up
    releaseProfile(profile);
    return null;
  }

  // Verify port is in use
  if (!isPortInUse(parseInt(port, 10))) {
    releaseProfile(profile);
    return null;
  }

  return { port: parseInt(port, 10), pid: parseInt(pid, 10), startTime: parseInt(startTime, 10) };
}

function assignPortForProfile(profile) {
  initRegistry();

  // Check if profile is already in use
  const existing = isProfileInUse(profile);
  if (existing) {
    const elapsed = Math.floor(Date.now() / 1000) - existing.startTime;
    const mins = Math.floor(elapsed / 60);
    const secs = elapsed % 60;

    console.error(`\nERROR: Profile '${profile}' is already in use\n`);
    console.error('Details:');
    console.error(`  Process ID: ${existing.pid}`);
    console.error(`  CDP Port: ${existing.port}`);
    console.error(`  Running for: ${mins > 0 ? `${mins}m ${secs}s` : `${secs}s`}\n`);

    return null;
  }

  // Get preferred port for this profile
  const preferredPort = getProfilePort(profile);

  // Read current registry
  const lines = fs.readFileSync(PORT_REGISTRY, 'utf8').split('\n').filter(Boolean);
  const usedPorts = new Set(lines.map(l => parseInt(l.split(':')[1], 10)));

  // Try preferred port first
  if (!usedPorts.has(preferredPort) && !isPortInUse(preferredPort)) {
    const startTime = Math.floor(Date.now() / 1000);
    fs.appendFileSync(PORT_REGISTRY, `${profile}:${preferredPort}:${process.pid}:${startTime}\n`);
    return preferredPort;
  }

  // Find next available port
  for (let port = 9222; port <= 9299; port++) {
    if (usedPorts.has(port)) continue;
    if (isPortInUse(port)) continue;

    const startTime = Math.floor(Date.now() / 1000);
    fs.appendFileSync(PORT_REGISTRY, `${profile}:${port}:${process.pid}:${startTime}\n`);
    return port;
  }

  console.error('\nERROR: No available CDP ports (9222-9299 all in use)\n');
  return null;
}

function releaseProfile(profile) {
  initRegistry();

  const lines = fs.readFileSync(PORT_REGISTRY, 'utf8').split('\n').filter(Boolean);
  const filtered = lines.filter(line => !line.startsWith(`${profile}:`));
  fs.writeFileSync(PORT_REGISTRY, filtered.join('\n') + (filtered.length ? '\n' : ''));
}

// ============================================================================
// CDP Connection Management
// ============================================================================

async function cdpIsRunning() {
  return new Promise((resolve) => {
    const req = http.get(`http://${CDP_HOST}:${CDP_PORT}/json/version`, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => resolve(data.includes('"Browser"')));
    });
    req.on('error', () => resolve(false));
    req.setTimeout(1000, () => { req.destroy(); resolve(false); });
  });
}

async function cdpIsHeadless() {
  return new Promise((resolve) => {
    const req = http.get(`http://${CDP_HOST}:${CDP_PORT}/json/version`, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          const info = JSON.parse(data);
          // Check both Browser field and User-Agent for "Headless"
          const isHeadless = (info.Browser && info.Browser.includes('Headless')) ||
                            (info['User-Agent'] && info['User-Agent'].includes('Headless'));
          resolve(isHeadless);
        } catch {
          resolve(false);
        }
      });
    });
    req.on('error', () => resolve(false));
    req.setTimeout(1000, () => { req.destroy(); resolve(false); });
  });
}

async function closeChromeInstance() {
  try {
    const client = await CDP({ port: CDP_PORT, host: CDP_HOST });
    const { Browser } = client;
    await Browser.close();
  } catch {
    // Ignore errors - Chrome might already be closed
  }
  // Wait for port to be released
  await new Promise(r => setTimeout(r, 500));
}

async function waitForCdp(timeout = 30) {
  const start = Date.now();
  while (Date.now() - start < timeout * 1000) {
    if (await cdpIsRunning()) return true;
    await new Promise(r => setTimeout(r, 200));
  }
  return false;
}

async function ensureChromeRunning() {
  // For named profiles, use hash-based port assignment
  if (PROFILE) {
    CDP_PORT = getProfilePort(PROFILE);
  }

  // Check if Chrome is already running on our port
  if (await cdpIsRunning()) {
    // Check if mode matches (headless vs headed)
    const isHeadless = await cdpIsHeadless();
    const wantHeadless = PROFILE && !DEBUG_MODE;

    if (DEBUG_MODE && isHeadless) {
      // User wants headed but we have headless - restart Chrome
      console.log('Restarting Chrome in headed mode...');
      await closeChromeInstance();
      await new Promise(r => setTimeout(r, 1000)); // Wait for port to be released
      // Continue to start new instance below
    } else if (wantHeadless && !isHeadless) {
      // User wants headless but we have headed - restart Chrome
      console.log('Restarting Chrome in headless mode...');
      await closeChromeInstance();
      await new Promise(r => setTimeout(r, 1000)); // Wait for port to be released
      // Continue to start new instance below
    } else {
      // Mode matches, use existing instance
      return true;
    }
  }

  // Determine profile path
  const profilePath = PROFILE_PATH || DEFAULT_PROFILE;
  fs.mkdirSync(profilePath, { recursive: true });

  // Build Chrome args
  const args = [
    `--remote-debugging-port=${CDP_PORT}`,
    `--user-data-dir=${profilePath}`,
    '--no-first-run',
    '--no-default-browser-check'
  ];

  // Headless mode: --profile without --debug
  if (PROFILE && !DEBUG_MODE) {
    args.push('--headless=new', '--disable-gpu');
  }

  const chrome = spawn(CHROME_APP, args, {
    detached: true,
    stdio: 'ignore'
  });
  chrome.unref();

  if (!await waitForCdp(30)) {
    console.error(`ERROR: Chrome failed to start (CDP not available on port ${CDP_PORT})`);
    process.exit(1);
  }
  return true;
}

async function connectCDP() {
  await ensureChromeRunning();
  try {
    return await CDP({ port: CDP_PORT, host: CDP_HOST });
  } catch (error) {
    console.error(`Failed to connect to Chrome CDP on ${CDP_HOST}:${CDP_PORT}`);
    console.error(`Error: ${error.message}`);
    process.exit(1);
  }
}

// ============================================================================
// Utility Functions
// ============================================================================

function isCoordinates(args) {
  return args.length >= 2 &&
         !isNaN(parseFloat(args[0])) &&
         !isNaN(parseFloat(args[1]));
}

function loadScript(name) {
  return fs.readFileSync(path.join(SCRIPT_DIR, 'js', name), 'utf8');
}

function formatTimeAgo(seconds) {
  if (seconds < 60) return 'just now';
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`;
  if (seconds < 86400) return `${Math.floor(seconds / 3600)}h ago`;
  return `${Math.floor(seconds / 86400)}d ago`;
}

// ============================================================================
// Snapshot with Smart Diff
// ============================================================================

async function getSnapshotPrefix(client) {
  const { Runtime } = client;
  const result = await Runtime.evaluate({
    expression: 'location.hostname + location.pathname',
    returnByValue: true
  });
  return result.result.value
    .replace(/[/:?&=]/g, '-')
    .replace(/-+/g, '-')
    .replace(/-$/, '');
}

async function getPageState(client) {
  const { Runtime } = client;
  const detectJs = loadScript('detect-page-state.js');
  const result = await Runtime.evaluate({ expression: detectJs, returnByValue: true });
  return result.result.value;
}

async function cmdSnapshot(clientOrFull, forceFull = false) {
  let client, shouldClose = false;

  if (clientOrFull === true || clientOrFull === false) {
    forceFull = clientOrFull;
    client = await connectCDP();
    shouldClose = true;
  } else if (clientOrFull) {
    client = clientOrFull;
  } else {
    client = await connectCDP();
    shouldClose = true;
  }

  const { Runtime } = client;

  try {
    const prefix = await getSnapshotPrefix(client);
    const state = await getPageState(client);
    const timestamp = Math.floor(Date.now() / 1000);
    const snapshotFile = path.join(SNAPSHOT_DIR, `${prefix}-${state}-${timestamp}.md`);

    const html2mdJs = `window.__RECON_FULL__ = true; ${loadScript('html2md.js')}`;
    const result = await Runtime.evaluate({ expression: html2mdJs, returnByValue: true });
    const content = result.result.value;

    // Handle case where page is navigating or content is unavailable
    if (!content) {
      console.log('(page loading...)');
      return;
    }

    // Smart diff by default (unless --full specified)
    if (!forceFull) {
      // Find latest snapshot with same prefix and state
      const pattern = `${prefix}-${state}-`;
      const files = fs.readdirSync(SNAPSHOT_DIR)
        .filter(f => f.startsWith(pattern) && f.endsWith('.md'))
        .sort()
        .reverse();

      if (files.length > 0) {
        const latestFile = path.join(SNAPSHOT_DIR, files[0]);
        const latestContent = fs.readFileSync(latestFile, 'utf8');

        // Save new snapshot
        fs.writeFileSync(snapshotFile, content);

        // Show diff if different
        if (content !== latestContent) {
          const oldLines = latestContent.split('\n');
          const newLines = content.split('\n');

          // Simple diff output
          const added = newLines.filter(l => !oldLines.includes(l));
          const removed = oldLines.filter(l => !newLines.includes(l));

          if (removed.length > 0) {
            removed.forEach(l => console.log(`- ${l}`));
          }
          if (added.length > 0) {
            added.forEach(l => console.log(`+ ${l}`));
          }
        } else {
          console.log('(no changes)');
        }
      } else {
        // No previous snapshot - show full
        fs.writeFileSync(snapshotFile, content);
        console.log(content);
      }
    } else {
      // Force full
      fs.writeFileSync(snapshotFile, content);
      console.log(content);
    }
  } finally {
    if (shouldClose) await client.close();
  }
}

// ============================================================================
// Commands
// ============================================================================

async function cmdOpen(url) {
  if (!url) {
    console.error('Usage: browser open URL');
    process.exit(1);
  }

  const client = await connectCDP();
  const { Page, Runtime } = client;

  try {
    await Page.enable();

    // Navigate and wait for load with timeout
    await Page.navigate({ url });

    // Wait for page load with timeout (don't use loadEventFired directly - it can hang)
    await Promise.race([
      new Promise(resolve => Page.loadEventFired(resolve)),
      new Promise(resolve => setTimeout(resolve, 10000)) // 10s timeout
    ]);

    // Additional wait for dynamic content
    await new Promise(r => setTimeout(r, 500));

    // Run inspect and format output
    const inspectJs = loadScript('inspect.js');
    const result = await Runtime.evaluate({ expression: inspectJs, returnByValue: true });
    const data = JSON.parse(result.result.value);

    formatInspectOutput(data);

    // Also show snapshot
    await cmdSnapshot(client, false);

  } finally {
    await client.close();
  }
}

async function cmdExecute(jsCode) {
  if (!jsCode) {
    console.error('Usage: browser execute "javascript code"');
    process.exit(1);
  }

  const client = await connectCDP();
  const { Runtime } = client;

  try {
    const result = await Runtime.evaluate({ expression: jsCode, returnByValue: true });
    if (result.result.value !== undefined) {
      console.log(result.result.value);
    }
  } finally {
    await client.close();
  }
}

async function cmdClick(args) {
  if (args.length === 0) {
    console.error('Usage: browser click "selector" [--index N]');
    console.error('       browser click X Y');
    process.exit(1);
  }

  if (isCoordinates(args)) {
    await cmdClickCoordinates(parseFloat(args[0]), parseFloat(args[1]));
  } else {
    await cmdClickSelector(args);
  }
}

async function cmdClickCoordinates(x, y) {
  const client = await connectCDP();
  const { Input } = client;

  try {
    await Input.dispatchMouseEvent({ type: 'mousePressed', x, y, button: 'left', clickCount: 1 });
    await Input.dispatchMouseEvent({ type: 'mouseReleased', x, y, button: 'left', clickCount: 1 });
    console.log(`✓ Clicked at (${x}, ${y})`);
    await cmdSnapshot(client);
  } finally {
    await client.close();
  }
}

async function cmdClickSelector(args) {
  let selector = '', index = null;

  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--index' && args[i + 1]) {
      index = parseInt(args[++i], 10);
    } else if (!selector) {
      selector = args[i];
    }
  }

  const client = await connectCDP();
  const { Runtime } = client;

  try {
    const interactJs = buildInteractJs(selector, null, index, 'click');
    const result = await Runtime.evaluate({ expression: interactJs, returnByValue: true });
    const response = JSON.parse(result.result.value);

    console.log(`${response.status}: ${response.message}`);

    if (response.status === 'OK') {
      // Wait for potential page navigation/updates
      await new Promise(r => setTimeout(r, 500));

      // Check if page is still loading (navigation might have occurred)
      const { Page } = client;
      await Page.enable();

      // Wait for page to be ready with timeout
      await Promise.race([
        new Promise(async resolve => {
          try {
            // Wait for load event or timeout
            const checkReady = async () => {
              const { result } = await Runtime.evaluate({
                expression: 'document.readyState',
                returnByValue: true
              });
              if (result.value === 'complete') {
                resolve();
              } else {
                setTimeout(checkReady, 100);
              }
            };
            await checkReady();
          } catch {
            resolve(); // Ignore errors, proceed with snapshot
          }
        }),
        new Promise(resolve => setTimeout(resolve, 5000)) // 5s timeout
      ]);

      await cmdSnapshot(client);
    }
  } finally {
    await client.close();
  }
}

async function cmdHover(args) {
  if (args.length === 0) {
    console.error('Usage: browser hover "selector" [--index N]');
    console.error('       browser hover X Y');
    process.exit(1);
  }

  if (isCoordinates(args)) {
    await cmdHoverCoordinates(parseFloat(args[0]), parseFloat(args[1]));
  } else {
    await cmdHoverSelector(args);
  }
}

async function cmdHoverCoordinates(x, y) {
  const client = await connectCDP();
  const { Input } = client;

  try {
    await Input.dispatchMouseEvent({ type: 'mouseMoved', x, y });
    console.log(`✓ Hovered at (${x}, ${y})`);
    await cmdSnapshot(client);
  } finally {
    await client.close();
  }
}

async function cmdHoverSelector(args) {
  let selector = '', index = null;

  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--index' && args[i + 1]) {
      index = parseInt(args[++i], 10);
    } else if (!selector) {
      selector = args[i];
    }
  }

  const client = await connectCDP();
  const { Runtime } = client;

  try {
    const interactJs = buildInteractJs(selector, null, index, 'hover');
    const result = await Runtime.evaluate({ expression: interactJs, returnByValue: true });
    const response = JSON.parse(result.result.value);

    console.log(`${response.status}: ${response.message}`);

    if (response.status === 'OK') {
      await new Promise(r => setTimeout(r, 300));
      await cmdSnapshot(client);
    }
  } finally {
    await client.close();
  }
}

async function cmdInput(args) {
  if (args.length < 2) {
    console.error('Usage: browser input "selector" "value" [--index N]');
    process.exit(1);
  }

  let selector = '', value = '', index = null;

  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--index' && args[i + 1]) {
      index = parseInt(args[++i], 10);
    } else if (!selector) {
      selector = args[i];
    } else if (!value) {
      value = args[i];
    }
  }

  const client = await connectCDP();
  const { Runtime } = client;

  try {
    const interactJs = buildInteractJs(selector, value, index, 'click');
    const result = await Runtime.evaluate({ expression: interactJs, returnByValue: true });
    const response = JSON.parse(result.result.value);

    console.log(`${response.status}: ${response.message}`);

    if (response.status === 'OK') {
      await cmdSnapshot(client);
    }
  } finally {
    await client.close();
  }
}

async function cmdDrag(args) {
  if (args.length < 2) {
    console.error('Usage: browser drag "source" "target" [--index N]');
    console.error('       browser drag X1 Y1 X2 Y2');
    process.exit(1);
  }

  if (args.length >= 4 && isCoordinates(args)) {
    await cmdDragCoordinates(
      parseFloat(args[0]), parseFloat(args[1]),
      parseFloat(args[2]), parseFloat(args[3])
    );
  } else {
    await cmdDragSelector(args);
  }
}

async function cmdDragCoordinates(x1, y1, x2, y2) {
  const client = await connectCDP();
  const { Input } = client;

  try {
    await Input.dispatchMouseEvent({ type: 'mousePressed', x: x1, y: y1, button: 'left' });
    await Input.dispatchMouseEvent({ type: 'mouseMoved', x: x2, y: y2 });
    await Input.dispatchMouseEvent({ type: 'mouseReleased', x: x2, y: y2, button: 'left' });
    console.log(`✓ Dragged from (${x1}, ${y1}) to (${x2}, ${y2})`);
    await cmdSnapshot(client);
  } finally {
    await client.close();
  }
}

async function cmdDragSelector(args) {
  let source = '', target = '', index = null;

  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--index' && args[i + 1]) {
      index = parseInt(args[++i], 10);
    } else if (!source) {
      source = args[i];
    } else if (!target) {
      target = args[i];
    }
  }

  const client = await connectCDP();
  const { Runtime } = client;

  try {
    const interactJs = buildInteractJs(source, null, index, 'drag', target);
    const result = await Runtime.evaluate({ expression: interactJs, returnByValue: true });
    const response = JSON.parse(result.result.value);

    console.log(`${response.status}: ${response.message}`);

    if (response.status === 'OK') {
      await cmdSnapshot(client);
    }
  } finally {
    await client.close();
  }
}

async function cmdScreenshot(args) {
  const client = await connectCDP();
  const { Page } = client;

  try {
    await Page.enable();
    const { data } = await Page.captureScreenshot({ format: 'jpeg', quality: 70 });

    const filename = `/tmp/screenshot-${new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19)}.jpg`;
    fs.writeFileSync(filename, Buffer.from(data, 'base64'));

    console.log(`Screenshot saved: ${filename}`);
    console.log('Use Read tool to view the image.');
  } finally {
    await client.close();
  }
}

async function cmdTabs() {
  const client = await connectCDP();
  const { Target } = client;

  try {
    const { targetInfos } = await Target.getTargets();
    const pages = targetInfos.filter(t => t.type === 'page');

    pages.forEach((page, i) => {
      console.log(`[${i}] ${page.url}`);
      console.log(`    ${page.title}`);
    });
  } finally {
    await client.close();
  }
}

async function cmdWait(selector) {
  const client = await connectCDP();
  const { Runtime } = client;

  try {
    if (selector) {
      // Wait for element
      const waitJs = `
        new Promise((resolve) => {
          const check = () => {
            if (document.querySelector(${JSON.stringify(selector)})) {
              resolve('OK');
            } else {
              setTimeout(check, 100);
            }
          };
          check();
          setTimeout(() => resolve('TIMEOUT'), 10000);
        })
      `;
      const result = await Runtime.evaluate({ expression: waitJs, awaitPromise: true, returnByValue: true });
      console.log(`OK: ${result.result.value === 'OK' ? 'Element found' : 'Timeout'}`);
    } else {
      // Wait for DOM stability
      await new Promise(r => setTimeout(r, 500));
      console.log('OK: Ready');
    }
  } finally {
    await client.close();
  }
}

async function cmdSendkey(key) {
  if (!key) {
    console.error('Usage: browser sendkey KEY');
    console.error('Keys: esc, enter, tab, up, down, left, right, backspace, delete');
    process.exit(1);
  }

  const keyMap = {
    'esc': 'Escape', 'escape': 'Escape',
    'enter': 'Enter', 'return': 'Enter',
    'tab': 'Tab',
    'up': 'ArrowUp', 'down': 'ArrowDown',
    'left': 'ArrowLeft', 'right': 'ArrowRight',
    'backspace': 'Backspace',
    'delete': 'Delete'
  };

  const keyName = keyMap[key.toLowerCase()] || key;

  const client = await connectCDP();
  const { Input } = client;

  try {
    await Input.dispatchKeyEvent({ type: 'keyDown', key: keyName });
    await Input.dispatchKeyEvent({ type: 'keyUp', key: keyName });
    console.log(`OK: sent ${keyName}`);
    await cmdSnapshot(client);
  } finally {
    await client.close();
  }
}

async function cmdInspect() {
  const client = await connectCDP();
  const { Runtime } = client;

  try {
    const inspectJs = loadScript('inspect.js');
    const result = await Runtime.evaluate({ expression: inspectJs, returnByValue: true });
    const data = JSON.parse(result.result.value);
    formatInspectOutput(data);
  } finally {
    await client.close();
  }
}

async function cmdClose() {
  if (!await cdpIsRunning()) {
    console.log('No Chrome instance running');
    return;
  }

  const client = await connectCDP();
  const { Browser } = client;

  try {
    await Browser.close();
    console.log('Chrome closed');
  } catch {
    console.log('Chrome closed');
  } finally {
    if (PROFILE) {
      releaseProfile(PROFILE);
    }
  }
}

// ============================================================================
// Profile Command
// ============================================================================

async function cmdProfile(args) {
  const subcommand = args[0] || 'list';
  const subArgs = args.slice(1);

  switch (subcommand) {
    case 'list':
      cmdProfileList();
      break;
    case 'create':
      await cmdProfileCreate(subArgs[0]);
      break;
    case 'enable':
      cmdProfileEnable(subArgs[0]);
      break;
    case 'disable':
      cmdProfileDisable(subArgs[0]);
      break;
    case 'rename':
      cmdProfileRename(subArgs[0], subArgs[1]);
      break;
    default:
      console.error(`Unknown profile subcommand: ${subcommand}`);
      console.error('\nUsage: profile <command> [args...]\n');
      console.error('Commands:');
      console.error('  list                List all profiles (default)');
      console.error('  create URL          Create new profile by logging in');
      console.error('  enable NAME         Enable a profile');
      console.error('  disable NAME        Disable a profile');
      console.error('  rename OLD NEW      Rename a profile');
      process.exit(1);
  }
}

function cmdProfileList() {
  if (!fs.existsSync(PROFILES_DIR)) {
    console.log('No profiles found\n');
    console.log('Create a profile:');
    console.log(`  ${TOOL_NAME} profile create URL\n`);
    return;
  }

  const dirs = fs.readdirSync(PROFILES_DIR).filter(name => {
    return fs.statSync(path.join(PROFILES_DIR, name)).isDirectory();
  });

  if (dirs.length === 0) {
    console.log('No profiles found\n');
    console.log('Create a profile:');
    console.log(`  ${TOOL_NAME} profile create URL\n`);
    return;
  }

  console.log('Profiles:\n');

  for (const name of dirs) {
    const profilePath = path.join(PROFILES_DIR, name);
    const display = readProfileMetadata(profilePath, 'display');
    const status = readProfileMetadata(profilePath, 'status');

    if (display) {
      if (status === 'disabled') {
        console.log(`  ${display} [DISABLED]`);
      } else {
        console.log(`  ${display}`);
      }
      console.log(`    Filename: ${name}`);
    } else {
      console.log(`  ${name} (no metadata)`);
    }
    console.log('');
  }
}

async function cmdProfileCreate(url) {
  if (!url) {
    console.error('Usage: profile create URL\n');
    console.error('Example:');
    console.error(`  ${TOOL_NAME} profile create https://mail.google.com`);
    process.exit(1);
  }

  const service = getServiceName(url);

  console.log(`Creating profile for <${service}>...\n`);

  // Show existing profiles for this service
  if (fs.existsSync(PROFILES_DIR)) {
    const serviceProfiles = [];
    for (const name of fs.readdirSync(PROFILES_DIR)) {
      const profilePath = path.join(PROFILES_DIR, name);
      if (!fs.statSync(profilePath).isDirectory()) continue;

      const profService = readProfileMetadata(profilePath, 'service');
      if (profService === service) {
        const profAccount = readProfileMetadata(profilePath, 'account');
        if (profAccount) serviceProfiles.push(profAccount);
      }
    }

    if (serviceProfiles.length > 0) {
      console.log(`Existing <${service}> profiles:`);
      serviceProfiles.forEach(acc => console.log(`  - ${acc}`));
      console.log('');
    }
  }

  // Prompt for account identifier
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout
  });

  const account = await new Promise(resolve => {
    rl.question('Account identifier (email/username): ', answer => {
      rl.close();
      resolve(answer.trim());
    });
  });

  if (!account) {
    console.error('Error: Account identifier is required');
    process.exit(1);
  }

  // Create profile directory
  const profileName = `${service}-${normalizeProfileName(account)}`;
  const profilePath = path.join(PROFILES_DIR, profileName);

  if (fs.existsSync(profilePath)) {
    console.error(`Error: Profile '${profileName}' already exists`);
    process.exit(1);
  }

  fs.mkdirSync(profilePath, { recursive: true });

  // Write metadata
  writeProfileMetadata(profilePath, service, account, 'manual', 'created');

  console.log(`\nOpening browser for login...`);
  console.log('Please login to your account, then close the browser window.\n');

  // Launch Chrome in headed mode for manual login
  const chrome = spawn(CHROME_APP, [
    `--remote-debugging-port=0`, // Use random port
    `--user-data-dir=${profilePath}`,
    '--no-first-run',
    '--no-default-browser-check',
    url
  ], {
    stdio: 'inherit' // Show Chrome output
  });

  // Wait for Chrome to close
  await new Promise(resolve => {
    chrome.on('close', resolve);
  });

  console.log(`\n✓ Profile created: <${service}> ${account} (manual)`);
  console.log(`  Filename: ${profileName}`);
}

function cmdProfileEnable(name) {
  if (!name) {
    console.error('Usage: profile enable NAME');
    process.exit(1);
  }

  let profilePath = path.join(PROFILES_DIR, name);

  // Try fuzzy match if exact doesn't exist
  if (!fs.existsSync(profilePath)) {
    const matches = fuzzyMatchProfile(name);
    if (matches.length === 0) {
      console.error(`Error: Profile '${name}' not found`);
      process.exit(1);
    }
    if (matches.length === 1) {
      name = matches[0];
      profilePath = path.join(PROFILES_DIR, name);
    } else {
      console.error(`Multiple matches found: ${matches.join(', ')}`);
      process.exit(1);
    }
  }

  const status = readProfileMetadata(profilePath, 'status');
  if (status === 'enabled') {
    console.log(`Profile '${name}' is already enabled`);
    return;
  }

  updateProfileMetadata(profilePath, 'status', 'enabled');
  console.log(`✓ Profile '${name}' enabled`);
}

function cmdProfileDisable(name) {
  if (!name) {
    console.error('Usage: profile disable NAME');
    process.exit(1);
  }

  let profilePath = path.join(PROFILES_DIR, name);

  // Try fuzzy match if exact doesn't exist
  if (!fs.existsSync(profilePath)) {
    const matches = fuzzyMatchProfile(name);
    if (matches.length === 0) {
      console.error(`Error: Profile '${name}' not found`);
      process.exit(1);
    }
    if (matches.length === 1) {
      name = matches[0];
      profilePath = path.join(PROFILES_DIR, name);
    } else {
      console.error(`Multiple matches found: ${matches.join(', ')}`);
      process.exit(1);
    }
  }

  const status = readProfileMetadata(profilePath, 'status');
  if (status === 'disabled') {
    console.log(`Profile '${name}' is already disabled`);
    return;
  }

  updateProfileMetadata(profilePath, 'status', 'disabled');
  console.log(`✓ Profile '${name}' disabled`);
}

function cmdProfileRename(oldName, newName) {
  if (!oldName || !newName) {
    console.error('Usage: profile rename OLD_NAME NEW_NAME');
    process.exit(1);
  }

  const oldNormalized = normalizeProfileName(oldName);
  const newNormalized = normalizeProfileName(newName);
  const oldPath = path.join(PROFILES_DIR, oldNormalized);
  const newPath = path.join(PROFILES_DIR, newNormalized);

  if (!fs.existsSync(oldPath)) {
    console.error(`Error: Profile '${oldNormalized}' does not exist`);
    process.exit(1);
  }

  if (fs.existsSync(newPath)) {
    console.error(`Error: Profile '${newNormalized}' already exists`);
    process.exit(1);
  }

  fs.renameSync(oldPath, newPath);

  // Update metadata if exists
  const service = readProfileMetadata(newPath, 'service');
  const source = readProfileMetadata(newPath, 'source');
  if (service) {
    const newAccount = newName.replace(new RegExp(`^${service}-`), '');
    updateProfileMetadata(newPath, 'account', newAccount);
    updateProfileMetadata(newPath, 'display', `<${service}> ${newAccount} (${source})`);
  }

  console.log(`✓ Profile renamed: ${oldNormalized} -> ${newNormalized}`);
}

// ============================================================================
// Helper Functions
// ============================================================================

function buildInteractJs(selector, inputValue, index, action, dragTarget) {
  const escaped = (s) => s ? s.replace(/'/g, "\\'") : '';

  let js = `var INTERACT_SELECTOR='${escaped(selector)}';\n`;
  js += `var INTERACT_INPUT=${inputValue !== null ? `'${escaped(inputValue)}'` : 'undefined'};\n`;
  js += `var INTERACT_INDEX=${index !== null ? index : 'undefined'};\n`;
  js += `var INTERACT_ACTION='${action || 'click'}';\n`;
  js += `var INTERACT_DRAG_TARGET=${dragTarget ? `'${escaped(dragTarget)}'` : 'undefined'};\n`;
  js += loadScript('interact.js');

  return js;
}

function formatInspectOutput(data) {
  console.log('URL Parameter Discovery');
  console.log('='.repeat(60));
  console.log();

  const summary = data.summary || {};
  console.log('Summary:');
  console.log(`  Parameters from links: ${summary.paramsFromLinks || 0}`);
  console.log(`  Parameters from forms: ${summary.paramsFromForms || 0}`);
  console.log(`  Total forms found: ${summary.totalForms || 0}`);
  console.log();

  const params = data.urlParams || {};
  if (Object.keys(params).length > 0) {
    console.log('Discovered Parameters:');
    console.log('-'.repeat(60));
    for (const [name, info] of Object.entries(params)) {
      const source = info.source || 'unknown';
      const examples = (info.examples || []).slice(0, 3).map(e => `'${e}'`).join(', ');
      console.log(`  ${name.padEnd(20)} [${source.padStart(5)}] ${examples}`);
    }
    console.log();
  }

  const forms = data.forms || [];
  if (forms.length > 0) {
    console.log('Forms:');
    console.log('-'.repeat(60));
    for (const form of forms) {
      console.log(`  Form #${form.index || 0}: ${form.method || 'GET'} ${form.action || ''}`);
      for (const field of (form.fields || [])) {
        console.log(`    - ${(field.name || '').padEnd(20)} (${field.type || ''})`);
      }
    }
    console.log();
  }

  if (summary.patternUrl) {
    console.log('URL Pattern:');
    console.log('-'.repeat(60));
    console.log(`  ${summary.patternUrl}`);
    console.log();
  }
}

// ============================================================================
// Help
// ============================================================================

function showHelp() {
  console.log(`browser - Browser automation with CDP (Chrome DevTools Protocol)

Usage: browser [OPTIONS] <command> [args...]

OPTIONS:
  --profile NAME        Use named profile (enables headless by default)
  --debug               Use headed browser (visible window)

COMMANDS:

  Navigation:
    open URL              Navigate to URL and show page state
    snapshot [--full]     Show page state (smart diff by default)
    inspect               Discover URL parameters from page

  Interaction:
    click SELECTOR        Click element by CSS selector or text
    click X Y             Click at coordinates
    input SELECTOR VALUE  Set input value
    hover SELECTOR        Hover element
    hover X Y             Hover at coordinates
    drag SRC TARGET       Drag element to element
    drag X1 Y1 X2 Y2      Drag coordinates
    sendkey KEY           Send keyboard input (esc, enter, tab, etc.)

  Management:
    tabs                  List open tabs
    wait [SELECTOR]       Wait for DOM stability or element
    execute JS            Execute JavaScript code
    screenshot            Capture page screenshot
    close                 Close Chrome instance

  Profiles:
    profile               List all profiles
    profile create URL    Create new profile
    profile enable NAME   Enable a profile
    profile disable NAME  Disable a profile
    profile rename OLD NEW Rename a profile

  Options:
    --index N             Select Nth match when multiple elements found

EXAMPLES:
  browser open "https://google.com"
  browser click "Submit"
  browser input "#email" "user@example.com"
  browser --profile myaccount open "https://example.com"
  browser --profile myaccount --debug open "https://example.com"
`);
}

// ============================================================================
// Signal Handlers (cleanup on exit)
// ============================================================================

// Track if we should cleanup on exit (only for explicit close)
let shouldCleanupOnExit = false;

function cleanup() {
  if (PROFILE) {
    releaseProfile(PROFILE);
  }
}

process.on('SIGINT', () => {
  // User pressed Ctrl+C - cleanup registry
  cleanup();
  process.exit(130);
});

process.on('SIGTERM', () => {
  // Process terminated - cleanup registry
  cleanup();
  process.exit(143);
});

// Note: Don't cleanup on normal exit - Chrome keeps running in background
// Cleanup only happens on:
// 1. SIGINT/SIGTERM (user interrupt)
// 2. Explicit 'close' command (handled in cmdClose)

// ============================================================================
// Main
// ============================================================================

async function main() {
  const args = process.argv.slice(2);

  // Parse global flags
  let i = 0;
  while (i < args.length && args[i].startsWith('--')) {
    if (args[i] === '--profile' && args[i + 1]) {
      PROFILE = args[i + 1];
      PROFILE_PATH = expandProfilePath(PROFILE);
      i += 2;
    } else if (args[i] === '--debug') {
      DEBUG_MODE = true;
      i++;
    } else {
      break;
    }
  }

  const cmdArgs = args.slice(i);

  if (cmdArgs.length === 0 || cmdArgs[0] === 'help' || cmdArgs[0] === '--help' || cmdArgs[0] === '-h') {
    showHelp();
    process.exit(0);
  }

  const command = cmdArgs[0];
  const restArgs = cmdArgs.slice(1);

  try {
    switch (command) {
      case 'open':
        await cmdOpen(restArgs[0]);
        break;
      case 'snapshot':
        await cmdSnapshot(restArgs.includes('--full'));
        break;
      case 'inspect':
        await cmdInspect();
        break;
      case 'click':
        await cmdClick(restArgs);
        break;
      case 'hover':
        await cmdHover(restArgs);
        break;
      case 'input':
        await cmdInput(restArgs);
        break;
      case 'drag':
        await cmdDrag(restArgs);
        break;
      case 'sendkey':
        await cmdSendkey(restArgs[0]);
        break;
      case 'tabs':
        await cmdTabs();
        break;
      case 'wait':
        await cmdWait(restArgs[0]);
        break;
      case 'execute':
        await cmdExecute(restArgs[0]);
        break;
      case 'screenshot':
        await cmdScreenshot(restArgs);
        break;
      case 'close':
        await cmdClose();
        break;
      case 'profile':
        await cmdProfile(restArgs);
        break;
      default:
        console.error(`Unknown command: ${command}`);
        console.error('Run "browser help" for usage.');
        process.exit(1);
    }
  } catch (error) {
    console.error(`Error: ${error.message}`);
    process.exit(1);
  }
}

main();
