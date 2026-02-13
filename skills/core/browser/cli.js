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
const { createHash, createDecipheriv, createCipheriv, pbkdf2Sync } = require('crypto');
const readline = require('readline');

// ============================================================================
// Configuration
// ============================================================================

const SCRIPT_DIR = __dirname;
const TOOL_NAME = path.basename(SCRIPT_DIR);

// Browser paths
const CHROME_CANARY = '/Applications/Google Chrome Canary.app/Contents/MacOS/Google Chrome Canary';
const CHROMIUM = '/Applications/Chromium.app/Contents/MacOS/Chromium';

// Directories
const DATA_DIR = path.join(SCRIPT_DIR, 'data');
const SESSIONS_DIR = '/tmp/browser-sessions';  // Ephemeral session storage
const DEFAULT_SESSION = path.join(SESSIONS_DIR, 'default');
const SNAPSHOT_DIR = '/tmp/chrome-snapshots';
const PORT_REGISTRY = path.join(DATA_DIR, 'port-registry');

// CDP settings
let CDP_PORT = parseInt(process.env.CDP_PORT || '9222', 10);
let CDP_HOST = process.env.CDP_HOST || 'localhost';

// Global flags
let ACCOUNT = '';        // Format: "service", "service:user", "Profile/service", etc.
let ACCOUNT_SERVICE = '';
let ACCOUNT_USER = '';
let ACCOUNT_PROFILE = null;  // Chrome profile name (Default, Profile 1, etc.)
let SESSION_PATH = '';
let DEBUG_MODE = false;      // Headed browser (visible window)
let KEYLESS_MODE = false;    // Use profile copy instead of cookie injection

// Claude session ID for port assignment (one browser per Claude session)
const CLAUDE_SESSION_ID = process.env.CLAUDE_SESSION_ID || 'default';

// Ensure directories exist
fs.mkdirSync(DATA_DIR, { recursive: true });
fs.mkdirSync(SESSIONS_DIR, { recursive: true });
fs.mkdirSync(SNAPSHOT_DIR, { recursive: true });

// ============================================================================
// Account & Session Utilities
// ============================================================================

function normalizeAccountName(name) {
  return name.toLowerCase().replace(/[^a-z0-9]/g, '_').replace(/_+/g, '_');
}

function parseAccount(account) {
  // Parse account string formats:
  // - "service" (eg: "github")
  // - "service:username" (eg: "github:zhengyishen0")
  // - "Profile/service" (eg: "Default/github")
  // - "Profile/service:username" (eg: "Profile 1/gmail:user@example.com")

  let chromeProfile = null;
  let serviceStr = account;

  // Check for profile prefix (contains "/" and profile name before it)
  const slashIdx = account.indexOf('/');
  if (slashIdx > 0) {
    const possibleProfile = account.slice(0, slashIdx);
    // Check if it looks like a Chrome profile name
    if (possibleProfile === 'Default' || /^Profile \d+$/.test(possibleProfile)) {
      chromeProfile = possibleProfile;
      serviceStr = account.slice(slashIdx + 1);
    }
  }

  // Parse service and user from remaining string
  const parts = serviceStr.split(':');
  return {
    chromeProfile,
    service: parts[0].toLowerCase(),
    user: parts[1] || null
  };
}

function getSessionPath(account) {
  // Create session path from account identifier
  const normalized = normalizeAccountName(account);
  return path.join(SESSIONS_DIR, normalized);
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

// ============================================================================
// Port Registry and Session Locking
// ============================================================================

function initRegistry() {
  fs.mkdirSync(path.dirname(PORT_REGISTRY), { recursive: true });
  if (!fs.existsSync(PORT_REGISTRY)) {
    fs.writeFileSync(PORT_REGISTRY, '');
  }
}

function getSessionPort(session) {
  // Hash-based port assignment (9222-9299)
  const hash = createHash('md5').update(session).digest();
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

function isSessionInUse(session) {
  initRegistry();

  const lines = fs.readFileSync(PORT_REGISTRY, 'utf8').split('\n').filter(Boolean);
  const entry = lines.find(line => line.startsWith(`${session}:`));

  if (!entry) return null;

  // Format: session:port:pid:startTime:mode
  const [, port, pid, startTime, mode] = entry.split(':');

  // Verify process is still running
  if (!isProcessRunning(parseInt(pid, 10))) {
    // Stale entry, clean it up
    releaseSession(session);
    return null;
  }

  // Verify port is in use
  if (!isPortInUse(parseInt(port, 10))) {
    releaseSession(session);
    return null;
  }

  return {
    port: parseInt(port, 10),
    pid: parseInt(pid, 10),
    startTime: parseInt(startTime, 10),
    mode: mode || 'headless'  // Default to headless for old entries
  };
}

function assignPortForSession(session) {
  initRegistry();

  // Check if session is already in use
  const existing = isSessionInUse(session);
  if (existing) {
    // Session already running - reuse it
    return existing.port;
  }

  // Get preferred port for this session
  const preferredPort = getSessionPort(session);

  // Read current registry
  const lines = fs.readFileSync(PORT_REGISTRY, 'utf8').split('\n').filter(Boolean);
  const usedPorts = new Set(lines.map(l => parseInt(l.split(':')[1], 10)));

  // Try preferred port first
  if (!usedPorts.has(preferredPort) && !isPortInUse(preferredPort)) {
    const startTime = Math.floor(Date.now() / 1000);
    fs.appendFileSync(PORT_REGISTRY, `${session}:${preferredPort}:${process.pid}:${startTime}\n`);
    return preferredPort;
  }

  // Find next available port
  for (let port = 9222; port <= 9299; port++) {
    if (usedPorts.has(port)) continue;
    if (isPortInUse(port)) continue;

    const startTime = Math.floor(Date.now() / 1000);
    fs.appendFileSync(PORT_REGISTRY, `${session}:${port}:${process.pid}:${startTime}\n`);
    return port;
  }

  console.error('\nERROR: No available CDP ports (9222-9299 all in use)\n');
  return null;
}

function releaseSession(session) {
  initRegistry();

  const lines = fs.readFileSync(PORT_REGISTRY, 'utf8').split('\n').filter(Boolean);
  const filtered = lines.filter(line => !line.startsWith(`${session}:`));
  fs.writeFileSync(PORT_REGISTRY, filtered.join('\n') + (filtered.length ? '\n' : ''));
}

function getPortOwner(port) {
  initRegistry();

  const lines = fs.readFileSync(PORT_REGISTRY, 'utf8').split('\n').filter(Boolean);
  for (const line of lines) {
    const [session, p, pid] = line.split(':');
    if (parseInt(p, 10) === port) {
      // Verify process is still alive
      if (!isProcessRunning(parseInt(pid, 10))) {
        releaseSession(session);
        return null;
      }
      return { session, pid: parseInt(pid, 10) };
    }
  }
  return null;
}

function cleanupStaleEntries() {
  initRegistry();

  const lines = fs.readFileSync(PORT_REGISTRY, 'utf8').split('\n').filter(Boolean);
  const validLines = [];
  const staleEntries = [];

  for (const line of lines) {
    const [session, port, pid] = line.split(':');
    const pidNum = parseInt(pid, 10);
    const portNum = parseInt(port, 10);

    // Keep only if process is running AND port is in use
    if (isProcessRunning(pidNum) && isPortInUse(portNum)) {
      validLines.push(line);
    } else {
      staleEntries.push({ session, port: portNum, pid: pidNum });
    }
  }

  if (staleEntries.length > 0) {
    fs.writeFileSync(PORT_REGISTRY, validLines.join('\n') + (validLines.length ? '\n' : ''));
  }

  return staleEntries;
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
  // Clean up stale registry entries first
  const staleEntries = cleanupStaleEntries();
  if (staleEntries.length > 0) {
    console.log(`Cleaned up ${staleEntries.length} stale session(s): ${staleEntries.map(e => e.session).join(', ')}`);
  }

  // Use Claude session ID for port assignment (one browser per Claude session)
  const sessionName = CLAUDE_SESSION_ID;
  const preferredPort = getSessionPort(sessionName);

  // Check if session already has a registered port (and browser is still running)
  const existingSession = isSessionInUse(sessionName);
  if (existingSession) {
    CDP_PORT = existingSession.port;

    // Check if Chrome is already running on our port
    if (await cdpIsRunning()) {
      // Mode is sticky - only change if --debug is explicitly passed AND different
      const isHeadless = await cdpIsHeadless();

      if (DEBUG_MODE && isHeadless) {
        // User explicitly wants headed but we have headless - restart Chrome
        console.log('Restarting Chrome in headed mode...');
        await closeChromeInstance();
        await new Promise(r => setTimeout(r, 1000));
      } else {
        // Keep existing mode (sticky) - don't restart for missing --debug
        return true;
      }
    }
  } else {
    // Check if preferred port is owned by a different session (collision)
    const portOwner = getPortOwner(preferredPort);
    if (portOwner && portOwner.session !== sessionName) {
      console.log(`Port ${preferredPort} in use by session '${portOwner.session}', finding alternative...`);
      // Find next available port
      for (let port = 9222; port <= 9299; port++) {
        if (!isPortInUse(port) && !getPortOwner(port)) {
          CDP_PORT = port;
          console.log(`Using port ${port} for session '${sessionName}'`);
          break;
        }
      }
    } else {
      CDP_PORT = preferredPort;
    }
  }

  // Determine browser path
  // - Keyless mode: Chrome Canary (profile copy requires same keychain)
  // - Normal mode: Chromium (cookie injection works with any browser)
  const browserPath = KEYLESS_MODE ? CHROME_CANARY : CHROMIUM;

  // Determine session path
  let sessionPath;
  if (KEYLESS_MODE) {
    // Keyless mode: use profile copy session
    sessionPath = path.join(SESSIONS_DIR, 'keyless');

    // Copy Chrome profile to session directory if not already done
    const chromeDefault = path.join(CHROME_APP_DIR, 'Default');
    if (fs.existsSync(chromeDefault) && !fs.existsSync(path.join(sessionPath, 'Default'))) {
      console.log('Copying Chrome profile for keyless mode...');
      fs.mkdirSync(sessionPath, { recursive: true });
      execSync(`cp -r "${chromeDefault}" "${path.join(sessionPath, 'Default')}"`, { stdio: 'pipe' });
    }
  } else {
    // Normal mode: ephemeral session with cookie injection
    sessionPath = SESSION_PATH || DEFAULT_SESSION;
  }

  fs.mkdirSync(sessionPath, { recursive: true });

  // Build Chrome args
  const args = [
    `--remote-debugging-port=${CDP_PORT}`,
    `--user-data-dir=${sessionPath}`,
    '--no-first-run',
    '--no-default-browser-check',
    '--disable-session-crashed-bubble',
    '--disable-infobars'
  ];

  // Headless mode: always unless --debug flag is used
  if (!DEBUG_MODE) {
    args.push('--headless=new', '--disable-gpu');
  }

  // Always start with about:blank to prevent session restore
  args.push('about:blank');

  const chrome = spawn(browserPath, args, {
    detached: true,
    stdio: 'ignore'
  });
  chrome.unref();

  if (!await waitForCdp(30)) {
    console.error(`ERROR: Browser failed to start (CDP not available on port ${CDP_PORT})`);
    process.exit(1);
  }

  // Register session with Chrome's PID and mode
  const registrySession = CLAUDE_SESSION_ID;
  const startTime = Math.floor(Date.now() / 1000);
  const mode = DEBUG_MODE ? 'headed' : 'headless';
  // Remove any existing entry for this session first
  releaseSession(registrySession);
  // Format: session:port:pid:startTime:mode
  fs.appendFileSync(PORT_REGISTRY, `${registrySession}:${CDP_PORT}:${chrome.pid}:${startTime}:${mode}\n`);

  return true;
}

async function connectCDP() {
  await ensureChromeRunning();
  try {
    const client = await CDP({ port: CDP_PORT, host: CDP_HOST });

    // Inject cookies on-demand from Chrome if account specified (not in keyless mode)
    if (ACCOUNT && !KEYLESS_MODE) {
      await injectAccountCookies(client, ACCOUNT_SERVICE, ACCOUNT_USER, ACCOUNT_PROFILE);
    }

    return client;
  } catch (error) {
    console.error(`Failed to connect to Chrome CDP on ${CDP_HOST}:${CDP_PORT}`);
    console.error(`Error: ${error.message}`);
    process.exit(1);
  }
}

async function injectAccountCookies(client, service, user = null, chromeProfile = null) {
  // Get Chrome encryption key
  const chromeKey = getBrowserEncryptionKey('chrome');
  if (!chromeKey) {
    console.error('Warning: Could not get Chrome encryption key. Cookies not injected.');
    return;
  }

  // Find matching account in Chrome
  let chromeProfiles = getChromeProfiles();

  // If specific profile requested, filter to just that profile
  if (chromeProfile) {
    if (!chromeProfiles.includes(chromeProfile)) {
      console.error(`Warning: Chrome profile "${chromeProfile}" not found.`);
      return;
    }
    chromeProfiles = [chromeProfile];
  }

  let cookies = [];

  for (const profileName of chromeProfiles) {
    const profilePath = path.join(CHROME_APP_DIR, profileName);
    const cookiesDb = path.join(profilePath, 'Cookies');

    if (!fs.existsSync(cookiesDb)) continue;

    // If user specified, verify it matches
    if (user) {
      const detected = detectChromeAccountsWithDetails(profilePath, chromeKey, service);
      if (!detected[service]) continue;

      const matchingAccount = detected[service].find(a =>
        a.account === user || a.account.includes(user)
      );
      if (!matchingAccount) continue;
    }

    // Extract cookies for this service
    const extracted = extractChromeCookies(cookiesDb, chromeKey, service);
    if (extracted.length > 0) {
      cookies = extracted;
      break;  // Use first matching profile
    }
  }

  if (cookies.length === 0) {
    const profileHint = chromeProfile ? ` in profile "${chromeProfile}"` : '';
    console.error(`Warning: No ${service} cookies found in Chrome${profileHint}.`);
    return;
  }

  // Inject cookies via CDP
  await injectCookiesViaCDP(client, cookies);
}

async function injectCookiesViaCDP(client, cookies) {
  try {
    if (!Array.isArray(cookies) || cookies.length === 0) return;

    const { Network } = client;
    await Network.enable();

    // Clear existing cookies for domains we're about to inject
    // This prevents server-set cookies from overriding our injected ones
    const domains = [...new Set(cookies.map(c => c.domain.replace(/^\./, '')))];
    for (const domain of domains) {
      try {
        await Network.deleteCookies({ domain });
        await Network.deleteCookies({ domain: `.${domain}` });
      } catch (e) {
        // Ignore delete errors
      }
    }

    let injected = 0;
    for (const cookie of cookies) {
      try {
        // __Host- prefixed cookies require url instead of domain
        const isHostCookie = cookie.name.startsWith('__Host-');
        const domain = cookie.domain.replace(/^\./, '');

        const cookieParams = {
          name: cookie.name,
          value: cookie.value,
          path: cookie.path || '/',
          secure: cookie.secure || false,
          httpOnly: cookie.httpOnly || false,
          sameSite: cookie.sameSite || 'Lax'
        };

        if (isHostCookie) {
          // __Host- cookies: use url, no domain
          cookieParams.url = `https://${domain}${cookie.path || '/'}`;
        } else {
          // Regular cookies: use domain
          cookieParams.domain = cookie.domain;
        }

        const result = await Network.setCookie(cookieParams);
        if (result.success) injected++;
      } catch (e) {
        // Ignore individual cookie errors
      }
    }

    if (DEBUG_MODE) {
      console.log(`  Injected ${injected}/${cookies.length} cookies`);

      // Verify cookies are set
      const check = await Network.getCookies({ urls: [`https://${domains[0]}`] });
      console.log(`  Verification: ${check.cookies.length} cookies for ${domains[0]}`);
      const loggedIn = check.cookies.find(c => c.name === 'logged_in');
      if (loggedIn) {
        console.log(`  logged_in = ${loggedIn.value}`);
      }
    }
  } catch (e) {
    // Ignore cookie injection errors
    if (DEBUG_MODE) {
      console.log(`  Cookie injection error: ${e.message}`);
    }
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

    // Reminder for AI agents
    console.log('\n---\nNote: Read all results carefully before taking action.');
  } finally {
    if (shouldClose) await client.close();
  }
}

async function cmdSnapshotSelectors() {
  const client = await connectCDP();
  const { Runtime } = client;

  try {
    // JavaScript to extract all interactive elements with their selectors
    const extractJs = `
      (function() {
        const INTERACTIVE_SELECTORS = [
          'button', 'a', 'input', 'textarea', 'select',
          '[role="button"]', '[role="tab"]', '[role="link"]',
          '[role="menuitem"]', '[role="checkbox"]', '[onclick]'
        ];

        function isVisible(el) {
          const rect = el.getBoundingClientRect();
          const styles = window.getComputedStyle(el);
          return rect.width > 0 && rect.height > 0 &&
                 styles.display !== 'none' && styles.visibility !== 'hidden';
        }

        function getSelector(el) {
          // Build a unique selector for the element
          if (el.id) return '#' + el.id;

          // Try data-testid
          if (el.dataset.testid) return '[data-testid="' + el.dataset.testid + '"]';

          // Try aria-label
          const ariaLabel = el.getAttribute('aria-label');
          if (ariaLabel) return '[aria-label="' + ariaLabel.replace(/"/g, '\\\\"') + '"]';

          // Try unique class
          if (el.className && typeof el.className === 'string') {
            const classes = el.className.trim().split(/\\s+/).filter(c => c && !c.includes('.'));
            if (classes.length > 0) {
              // Use first few classes that are valid CSS identifiers
              const validClasses = classes.filter(c => /^[a-zA-Z_-][a-zA-Z0-9_-]*$/.test(c)).slice(0, 3);
              if (validClasses.length > 0) {
                const selector = el.tagName.toLowerCase() + '.' + validClasses.join('.');
                try {
                  const matches = document.querySelectorAll(selector);
                  if (matches.length === 1) return selector;
                } catch(e) {}
              }
            }
          }

          // Fallback: tag + nth-child
          const tag = el.tagName.toLowerCase();
          const parent = el.parentElement;
          if (parent) {
            const siblings = Array.from(parent.children).filter(c => c.tagName === el.tagName);
            if (siblings.length > 1) {
              const idx = siblings.indexOf(el) + 1;
              return tag + ':nth-of-type(' + idx + ')';
            }
          }
          return tag;
        }

        const elements = document.querySelectorAll(INTERACTIVE_SELECTORS.join(','));
        const results = [];

        elements.forEach(el => {
          if (!isVisible(el)) return;

          const tag = el.tagName.toLowerCase();
          const text = (el.innerText || '').trim().substring(0, 40);
          const selector = getSelector(el);
          const type = el.type || el.getAttribute('role') || tag;

          results.push({ selector, tag, type, text });
        });

        return JSON.stringify(results);
      })()
    `;

    const result = await Runtime.evaluate({ expression: extractJs, returnByValue: true });
    const elements = JSON.parse(result.result.value);

    console.log('Interactive Elements\n' + '='.repeat(60) + '\n');

    if (elements.length === 0) {
      console.log('No interactive elements found.\n');
    } else {
      // Group by type
      const grouped = {};
      elements.forEach(el => {
        const key = el.type || el.tag;
        if (!grouped[key]) grouped[key] = [];
        grouped[key].push(el);
      });

      for (const [type, els] of Object.entries(grouped)) {
        console.log(`${type.toUpperCase()} (${els.length})`);
        els.slice(0, 20).forEach(el => {
          const text = el.text ? ` "${el.text}"` : '';
          console.log(`  ${el.selector}${text}`);
        });
        if (els.length > 20) {
          console.log(`  ... and ${els.length - 20} more`);
        }
        console.log();
      }
    }

    console.log(`Total: ${elements.length} interactive elements`);
  } finally {
    await client.close();
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

    // Show browser status line
    let modeInfo = 'default session';
    if (ACCOUNT) modeInfo = `account: ${ACCOUNT}`;
    if (KEYLESS_MODE) modeInfo += ', keyless';
    if (DEBUG_MODE) modeInfo += ', headed';
    console.log(`Browser: open (${modeInfo}, port: ${CDP_PORT})\n`);

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
    console.log('No browser instance running');
    return;
  }

  const client = await CDP({ port: CDP_PORT, host: CDP_HOST });
  const { Browser } = client;

  try {
    await Browser.close();
    console.log('Browser closed');
  } catch {
    console.log('Browser closed');
  } finally {
    const sessionName = ACCOUNT || 'default';
    releaseSession(sessionName);
  }
}

// ============================================================================
// Chrome.app Profile Helpers
// ============================================================================

const CHROME_APP_DIR = path.join(process.env.HOME, 'Library/Application Support/Google/Chrome');

// Cookie encryption constants (macOS Chrome uses AES-128-CBC)
const COOKIE_SALT = 'saltysalt';
const COOKIE_ITERATIONS = 1003;
const COOKIE_KEY_LENGTH = 16;
const COOKIE_IV = Buffer.alloc(16, 0x20); // 16 space characters

function getBrowserEncryptionKey(browser) {
  const serviceName = browser === 'chrome' ? 'Chrome Safe Storage' : 'Chromium Safe Storage';
  const cacheFile = path.join(DATA_DIR, `.${browser}-key`);

  // Check cache first (avoids repeated Keychain prompts)
  if (fs.existsSync(cacheFile)) {
    try {
      const cached = fs.readFileSync(cacheFile, 'utf8').trim();
      return Buffer.from(cached, 'hex');
    } catch (err) {
      // Cache corrupted, will regenerate
    }
  }

  // Get encryption password from macOS Keychain (prompts user once)
  try {
    const password = execSync(`security find-generic-password -s "${serviceName}" -w`, {
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'pipe']
    }).trim();

    // Derive AES key using PBKDF2
    const key = pbkdf2Sync(password, COOKIE_SALT, COOKIE_ITERATIONS, COOKIE_KEY_LENGTH, 'sha1');

    // Cache the derived key (not the password)
    try {
      fs.writeFileSync(cacheFile, key.toString('hex'), { mode: 0o600 });
    } catch (err) {
      // Cache write failed, continue anyway
    }

    return key;
  } catch (err) {
    return null;
  }
}

function decryptCookieValue(encryptedValue, key) {
  if (!encryptedValue || encryptedValue.length < 4) return null;

  // Check for "v10" or "v11" prefix (macOS Chrome encryption marker)
  const prefix = encryptedValue.slice(0, 3).toString('utf8');
  if (prefix !== 'v10' && prefix !== 'v11') {
    // Not encrypted or unknown format
    return encryptedValue;
  }

  const ciphertext = encryptedValue.slice(3);
  try {
    const decipher = createDecipheriv('aes-128-cbc', key, COOKIE_IV);
    let decrypted = decipher.update(ciphertext);
    decrypted = Buffer.concat([decrypted, decipher.final()]);
    return decrypted;
  } catch (err) {
    return null;
  }
}

function encryptCookieValue(plainValue, key) {
  if (!plainValue) return null;

  try {
    const cipher = createCipheriv('aes-128-cbc', key, COOKIE_IV);
    let encrypted = cipher.update(plainValue);
    encrypted = Buffer.concat([encrypted, cipher.final()]);
    // Add "v10" prefix
    return Buffer.concat([Buffer.from('v10', 'utf8'), encrypted]);
  } catch (err) {
    return null;
  }
}

function reencryptCookiesDatabase(sourceCookiesDb, destCookiesDb, sourceKey, destKey) {
  // Copy the cookies database first
  execSync(`cp "${sourceCookiesDb}" "${destCookiesDb}"`);

  // Read all encrypted cookies
  const query = `SELECT rowid, encrypted_value FROM cookies WHERE length(encrypted_value) > 0`;
  let rows;
  try {
    const result = execSync(`sqlite3 "${destCookiesDb}" "${query}"`, {
      encoding: 'buffer',
      maxBuffer: 50 * 1024 * 1024 // 50MB buffer for large cookie databases
    });
    rows = result.toString('utf8').trim().split('\n').filter(Boolean);
  } catch (err) {
    console.error('Failed to read cookies:', err.message);
    return false;
  }

  if (rows.length === 0) {
    console.log('  No encrypted cookies to convert');
    return true;
  }

  console.log(`  Re-encrypting ${rows.length} cookies...`);

  // Process each cookie - we need to use a different approach since encrypted_value is binary
  // Use hex encoding for the binary data
  const hexQuery = `SELECT rowid, hex(encrypted_value) FROM cookies WHERE length(encrypted_value) > 0`;
  let hexResult;
  try {
    hexResult = execSync(`sqlite3 "${destCookiesDb}" "${hexQuery}"`, {
      encoding: 'utf8',
      maxBuffer: 50 * 1024 * 1024
    });
  } catch (err) {
    console.error('Failed to read cookies as hex:', err.message);
    return false;
  }

  const hexRows = hexResult.trim().split('\n').filter(Boolean);
  let converted = 0;
  let failed = 0;

  for (const row of hexRows) {
    const pipeIndex = row.indexOf('|');
    if (pipeIndex === -1) continue;

    const rowid = row.substring(0, pipeIndex);
    const hexValue = row.substring(pipeIndex + 1);
    const encryptedValue = Buffer.from(hexValue, 'hex');

    // Decrypt with source key
    const decrypted = decryptCookieValue(encryptedValue, sourceKey);
    if (!decrypted) {
      failed++;
      continue;
    }

    // Re-encrypt with dest key
    const reencrypted = encryptCookieValue(decrypted, destKey);
    if (!reencrypted) {
      failed++;
      continue;
    }

    // Update the cookie in the database
    const newHex = reencrypted.toString('hex');
    const updateQuery = `UPDATE cookies SET encrypted_value = x'${newHex}' WHERE rowid = ${rowid}`;
    try {
      execSync(`sqlite3 "${destCookiesDb}" "${updateQuery}"`, { stdio: 'pipe' });
      converted++;
    } catch (err) {
      failed++;
    }
  }

  console.log(`  Converted: ${converted}, Failed: ${failed}`);
  return converted > 0;
}

function extractChromeCookies(cookiesDb, chromeKey, service = null) {
  if (!fs.existsSync(cookiesDb)) return [];

  // Build domain filter if service specified
  let domainFilter = '';
  if (service) {
    const mappingsFile = path.join(SCRIPT_DIR, 'domain-mappings.json');
    if (fs.existsSync(mappingsFile)) {
      const mappings = JSON.parse(fs.readFileSync(mappingsFile, 'utf8'));
      const domains = Object.entries(mappings)
        .filter(([, svc]) => svc === service)
        .map(([domain]) => domain.replace(/^www\./, ''));

      if (domains.length > 0) {
        // Build SQL LIKE conditions for each domain
        const conditions = [...new Set(domains)].map(d => `host_key LIKE '%${d}%'`);
        domainFilter = `AND (${conditions.join(' OR ')})`;
      }
    }
  }

  // Query cookies with optional domain filter
  const query = `
    SELECT host_key, name, path, is_secure, is_httponly, samesite,
           expires_utc, hex(encrypted_value) as enc_hex
    FROM cookies
    WHERE length(encrypted_value) > 0
    ${domainFilter}
  `;

  let result;
  try {
    result = execSync(`sqlite3 -separator '|' "${cookiesDb}" "${query}"`, {
      encoding: 'utf8',
      maxBuffer: 50 * 1024 * 1024
    });
  } catch (err) {
    return [];
  }

  const cookies = [];
  const rows = result.trim().split('\n').filter(Boolean);

  for (const row of rows) {
    const parts = row.split('|');
    if (parts.length < 8) continue;

    const [host, name, cookiePath, secure, httpOnly, sameSite, expires, encHex] = parts;
    const encrypted = Buffer.from(encHex, 'hex');

    // Decrypt the cookie value
    const decrypted = decryptCookieValue(encrypted, chromeKey);
    if (!decrypted) continue;

    // Skip first 32 bytes (hash prefix), actual value starts at byte 32
    const value = decrypted.length > 32 ? decrypted.slice(32).toString('utf8') : decrypted.toString('utf8');

    // Map sameSite values: 0=None, 1=Lax, 2=Strict
    const sameSiteMap = { '0': 'None', '1': 'Lax', '2': 'Strict' };

    cookies.push({
      name,
      value,
      domain: host,
      path: cookiePath || '/',
      secure: secure === '1',
      httpOnly: httpOnly === '1',
      sameSite: sameSiteMap[sameSite] || 'Lax'
    });
  }

  return cookies;
}

function getChromeProfiles() {
  if (!fs.existsSync(CHROME_APP_DIR)) return [];

  return fs.readdirSync(CHROME_APP_DIR).filter(name => {
    // Only consider Default and Profile N directories
    if (name !== 'Default' && !/^Profile \d+$/.test(name)) return false;
    const fullPath = path.join(CHROME_APP_DIR, name);
    try {
      return fs.statSync(fullPath).isDirectory();
    } catch {
      return false;
    }
  });
}

// Get all Chrome profiles with details (skips System Profile, Guest Profile)
function getAllChromeProfiles() {
  if (!fs.existsSync(CHROME_APP_DIR)) return [];

  const skipProfiles = ['System Profile', 'Guest Profile', 'Crashpad', 'Crowd Deny',
                        'FileTypePolicies', 'GrShaderCache', 'MEIPreload', 'OnDeviceHeadSuggestModel',
                        'OptimizationGuidePredictionModels', 'SafetyTips', 'ShaderCache',
                        'TrustTokenKeyCommitments', 'ZxcvbnData', 'hyphen-data', 'pnacl'];

  return fs.readdirSync(CHROME_APP_DIR).filter(name => {
    // Skip known non-profile directories
    if (skipProfiles.includes(name)) return false;
    // Only consider Default and Profile N directories
    if (name !== 'Default' && !/^Profile \d+$/.test(name)) return false;
    const fullPath = path.join(CHROME_APP_DIR, name);
    try {
      // Must be a directory with Cookies database
      return fs.statSync(fullPath).isDirectory() &&
             fs.existsSync(path.join(fullPath, 'Cookies'));
    } catch {
      return false;
    }
  });
}

// Get registrable domain (strip subdomains)
function getRegistrableDomain(domain) {
  // Remove leading dot
  domain = domain.replace(/^\./, '');

  // Common multi-part TLDs
  const multiPartTlds = ['.co.uk', '.co.jp', '.com.au', '.com.br', '.co.nz'];
  for (const tld of multiPartTlds) {
    if (domain.endsWith(tld)) {
      const parts = domain.slice(0, -tld.length).split('.');
      return parts[parts.length - 1] + tld;
    }
  }

  // Standard TLD
  const parts = domain.split('.');
  if (parts.length >= 2) {
    return parts.slice(-2).join('.');
  }
  return domain;
}

// Score a cookie to detect if it's an auth/login cookie
function scoreCookieForAuth(cookieName, cookieValue) {
  let score = 0;

  // Check against known auth cookies
  for (const [service, cookieNames] of Object.entries(ACCOUNT_COOKIES)) {
    if (cookieNames.includes(cookieName)) {
      score += 10; // High confidence for known cookies
      break;
    }
  }

  // Check against auth patterns
  for (const pattern of AUTH_PATTERNS) {
    if (pattern.test(cookieName)) {
      score += 5;
      break;
    }
  }

  // Common auth cookie names
  const authNames = ['token', 'auth', 'session', 'logged', 'user', 'account', 'sid', 'ssid'];
  const lowerName = cookieName.toLowerCase();
  for (const name of authNames) {
    if (lowerName.includes(name)) {
      score += 2;
      break;
    }
  }

  // Value looks like a token (long alphanumeric string)
  if (cookieValue && cookieValue.length > 20 && /^[a-zA-Z0-9_-]+$/.test(cookieValue)) {
    score += 1;
  }

  return score;
}

// Extract account name from cookie value based on service
function extractAccountName(service, cookieName, cookieValue, profilePath) {
  // GitHub: dotcom_user contains username directly
  if (service === 'github' && cookieName === 'dotcom_user') {
    return cookieValue;
  }

  // Google services: get email from Chrome Preferences
  if (service && service.startsWith('google') || service === 'gmail') {
    const email = getGoogleEmailFromPreferences(profilePath);
    if (email) return email;
  }

  // Twitter: twid format is "u=1234567890"
  if (cookieName === 'twid') {
    const match = cookieValue.match(/u=(\d+)/);
    if (match) return `user:${match[1]}`;
  }

  // Facebook/Instagram: numeric user ID
  if (cookieName === 'c_user' || cookieName === 'ds_user_id') {
    return `user:${cookieValue}`;
  }

  // Cloudflare: curr-account is the account ID (may be JSON or plain ID, possibly URL-encoded)
  if (cookieName === 'curr-account' && cookieValue) {
    let value = cookieValue;
    // URL decode if needed
    if (value.includes('%')) {
      try {
        value = decodeURIComponent(value);
      } catch {
        // Keep original
      }
    }
    // Check if it's JSON
    if (value.startsWith('{')) {
      try {
        const parsed = JSON.parse(value);
        if (parsed.id) return parsed.id.substring(0, 12) + '...';
        if (parsed.account_id) return parsed.account_id.substring(0, 12) + '...';
        // Look for first key that looks like an account ID
        for (const key of Object.keys(parsed)) {
          if (/^[a-f0-9]{32}$/i.test(key)) {
            return key.substring(0, 12) + '...';
          }
        }
      } catch {
        // Not valid JSON, don't show partial JSON
        return null;
      }
    }
    // Plain value or fallback
    if (value.length > 16) {
      return value.substring(0, 12) + '...';
    }
    return value;
  }

  // Feishu: try to decode QXV0aHpDb250ZXh0 (AuthzContext)
  if (cookieName === 'QXV0aHpDb250ZXh0' && cookieValue) {
    try {
      const decoded = Buffer.from(cookieValue, 'base64').toString('utf8');
      // Look for email or username in decoded JSON
      const emailMatch = decoded.match(/"email"\s*:\s*"([^"]+)"/);
      if (emailMatch) return emailMatch[1];
      const userMatch = decoded.match(/"user(?:name|_name)"\s*:\s*"([^"]+)"/);
      if (userMatch) return userMatch[1];
    } catch {
      // Ignore decode errors
    }
  }

  // Claude/Anthropic: ajs_user_id might contain readable ID
  if (cookieName === 'ajs_user_id' && cookieValue) {
    // Check if it looks like a readable ID
    if (cookieValue.length < 40 && !cookieValue.includes('-')) {
      return cookieValue;
    }
  }

  return null; // No account name extracted
}

// Discover all logged-in accounts from Chrome's cookies
function discoverAllAccounts(profilePath, chromeKey, showAll = false) {
  const cookiesDb = path.join(profilePath, 'Cookies');
  if (!fs.existsSync(cookiesDb)) return { loggedIn: [], visited: [] };

  // Load domain mappings
  const mappingsFile = path.join(SCRIPT_DIR, 'domain-mappings.json');
  let mappings = {};
  if (fs.existsSync(mappingsFile)) {
    mappings = JSON.parse(fs.readFileSync(mappingsFile, 'utf8'));
  }

  // Create reverse mapping
  const domainToService = { ...mappings };
  // Add entries for registrable domains
  for (const [domain, service] of Object.entries(mappings)) {
    const registrable = getRegistrableDomain(domain);
    if (!domainToService[registrable]) {
      domainToService[registrable] = service;
    }
  }

  // Get saved logins from Login Data database (for account name lookup)
  const savedLogins = getSavedLogins(profilePath);

  // Chrome time epoch
  const CHROME_EPOCH_OFFSET = 11644473600000000n;
  const nowChrome = BigInt(Date.now()) * 1000n + CHROME_EPOCH_OFFSET;

  // Query ALL cookies from database
  const query = `
    SELECT host_key, name, hex(encrypted_value), last_access_utc, expires_utc
    FROM cookies
    WHERE last_access_utc > 0
    ORDER BY last_access_utc DESC
  `;

  let result;
  try {
    result = execSync(`sqlite3 -separator '|' "${cookiesDb}" "${query}"`, {
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'pipe'],
      maxBuffer: 50 * 1024 * 1024
    });
  } catch (err) {
    return { loggedIn: [], visited: [] };
  }

  // Group cookies by registrable domain
  const domainCookies = {}; // registrableDomain -> {cookies: [], subdomains: Set, lastAccess}

  for (const line of result.trim().split('\n')) {
    if (!line) continue;
    const parts = line.split('|');
    if (parts.length < 5) continue;

    const [rawDomain, cookieName, encHex, lastAccessStr, expiresStr] = parts;
    const domain = rawDomain.replace(/^\./, '');
    const registrable = getRegistrableDomain(domain);

    // Initialize domain entry
    if (!domainCookies[registrable]) {
      domainCookies[registrable] = {
        cookies: [],
        subdomains: new Set(),
        lastAccess: 0n,
        authScore: 0
      };
    }

    // Track subdomains
    if (domain !== registrable) {
      domainCookies[registrable].subdomains.add(domain);
    }

    // Update last access
    try {
      const lastAccess = BigInt(lastAccessStr);
      if (lastAccess > domainCookies[registrable].lastAccess) {
        domainCookies[registrable].lastAccess = lastAccess;
      }
    } catch {
      // Invalid last access value, skip
    }

    // Decrypt cookie value
    let value = null;
    if (chromeKey && encHex) {
      try {
        const encrypted = Buffer.from(encHex, 'hex');
        const decrypted = decryptCookieValue(encrypted, chromeKey);
        if (decrypted) {
          value = decrypted.length > 32 ?
            decrypted.slice(32).toString('utf8') :
            decrypted.toString('utf8');
        }
      } catch {
        // Ignore decryption errors
      }
    }

    // Score this cookie for auth detection
    const score = scoreCookieForAuth(cookieName, value);
    domainCookies[registrable].authScore += score;

    // Store cookie info
    let expired = false;
    try {
      expired = BigInt(expiresStr) < nowChrome;
    } catch {
      // Invalid expires value, assume not expired
    }
    domainCookies[registrable].cookies.push({
      name: cookieName,
      value,
      domain,
      score,
      expired
    });
  }

  // Process domains and categorize
  const loggedIn = [];
  const visited = [];

  for (const [registrable, info] of Object.entries(domainCookies)) {
    // Get service name
    let service = domainToService[registrable];
    if (!service) {
      // Try to derive from domain
      service = registrable
        .replace(/\.(com|org|net|io|co|app|dev)$/, '')
        .replace(/\./g, '-');
    }

    // Check if logged in (auth score > 5 indicates likely logged in)
    const isLoggedIn = info.authScore >= 5 && info.cookies.some(c => !c.expired && c.score > 0);

    // Try to extract account name from cookies first
    let accountName = null;
    for (const cookie of info.cookies.sort((a, b) => b.score - a.score)) {
      if (cookie.score > 0 && cookie.value) {
        accountName = extractAccountName(service, cookie.name, cookie.value, profilePath);
        if (accountName) break;
      }
    }

    // Fallback: look up account name from saved logins (Login Data)
    if (!accountName && savedLogins[registrable]) {
      accountName = savedLogins[registrable];
    }

    const secondsAgo = Number((nowChrome - info.lastAccess) / 1000000n);

    const entry = {
      service,
      domain: registrable,
      subdomains: info.subdomains.size,
      account: accountName,
      score: info.authScore,
      isLoggedIn,
      timeAgo: formatTimeAgo(secondsAgo),
      secondsAgo
    };

    if (isLoggedIn) {
      loggedIn.push(entry);
    } else {
      visited.push(entry);
    }
  }

  // Sort by score (highest first), then by recency
  loggedIn.sort((a, b) => b.score - a.score || a.secondsAgo - b.secondsAgo);
  visited.sort((a, b) => a.secondsAgo - b.secondsAgo);

  return { loggedIn, visited };
}

// Read Google account email from Chrome Preferences file
function getGoogleEmailFromPreferences(profilePath) {
  const prefsFile = path.join(profilePath, 'Preferences');
  if (!fs.existsSync(prefsFile)) return null;

  try {
    const prefs = JSON.parse(fs.readFileSync(prefsFile, 'utf8'));
    const accountInfo = prefs.account_info;
    if (Array.isArray(accountInfo) && accountInfo.length > 0) {
      // Return the first account's email (primary account)
      return accountInfo[0].email || null;
    }
  } catch (err) {
    // Ignore parse errors
  }
  return null;
}

function formatTimeAgo(seconds) {
  if (seconds < 60) return 'just now';
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`;
  if (seconds < 86400) return `${Math.floor(seconds / 3600)}h ago`;
  return `${Math.floor(seconds / 86400)}d ago`;
}

// Account identifier cookies for each service
const ACCOUNT_COOKIES = {
  'github': ['dotcom_user'],  // Contains username directly
  'gmail': ['OSID'],          // Google account indicator
  'google-calendar': ['OSID'],
  'google-docs': ['OSID'],
  'google-drive': ['OSID'],
  'google-sheets': ['OSID'],
  'google-slides': ['OSID'],
  'twitter': ['twid'],        // Contains user ID
  'linkedin': ['li_at'],      // Session token (no username, but indicates logged in)
  'amazon': ['at-main'],      // Auth token (no username)
  'facebook': ['c_user'],     // User ID
  'instagram': ['ds_user_id'], // User ID
  // New services
  'feishu': ['session', 'QXV0aHpDb250ZXh0'],  // AuthzContext base64
  'claude': ['ajs_user_id', 'sessionKey'],
  'anthropic': ['ajs_user_id', 'sessionKey'],
  'cloudflare': ['curr-account', '__cf_logged_in']
};

// Auth cookie patterns for auto-discovery
const AUTH_PATTERNS = [
  /^(session|auth|access)[-_]?(token|id)?$/i,
  /^(user|member|account)[-_]?(id|token|session)?$/i,
  /^logged[-_]?in$/i,
  /^(sid|ssid|_session|_auth)$/i
];

function detectChromeAccountsWithDetails(profilePath, chromeKey, targetService = null) {
  const cookiesDb = path.join(profilePath, 'Cookies');
  if (!fs.existsSync(cookiesDb)) return [];

  // Load domain mappings
  const mappingsFile = path.join(SCRIPT_DIR, 'domain-mappings.json');
  let mappings = {};
  if (fs.existsSync(mappingsFile)) {
    mappings = JSON.parse(fs.readFileSync(mappingsFile, 'utf8'));
  }

  // Reverse mapping: service -> domains
  const serviceDomains = {};
  for (const [domain, service] of Object.entries(mappings)) {
    if (!serviceDomains[service]) serviceDomains[service] = [];
    serviceDomains[service].push(domain);
  }

  // Chrome time epoch: Jan 1, 1601 (microseconds)
  const CHROME_EPOCH_OFFSET = 11644473600000000n;
  const nowChrome = BigInt(Date.now()) * 1000n + CHROME_EPOCH_OFFSET;

  // Build query for account-identifying cookies
  let accountCookieNames = new Set();
  for (const names of Object.values(ACCOUNT_COOKIES)) {
    names.forEach(n => accountCookieNames.add(n));
  }
  const cookieNameFilter = [...accountCookieNames].map(n => `name = '${n}'`).join(' OR ');

  // Query for account-identifying cookies with decryption
  const query = `
    SELECT host_key, name, hex(encrypted_value), last_access_utc, expires_utc
    FROM cookies
    WHERE (${cookieNameFilter})
      AND expires_utc > ${nowChrome}
      AND last_access_utc > 0
    ORDER BY last_access_utc DESC
  `;

  try {
    const result = execSync(`sqlite3 -separator '|' "${cookiesDb}" "${query}"`, {
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'pipe'],
      maxBuffer: 10 * 1024 * 1024
    });

    // Group by service with account info
    const serviceAccounts = {}; // service -> [{account, timeAgo, domain}]

    for (const line of result.trim().split('\n')) {
      if (!line) continue;
      const parts = line.split('|');
      if (parts.length < 5) continue;

      const [rawDomain, cookieName, encHex, lastAccessStr, expiresStr] = parts;
      const domain = rawDomain.replace(/^\./, '');

      // Find service for this domain
      const service = mappings[domain] || mappings[rawDomain];
      if (!service) continue;
      if (targetService && service !== targetService) continue;

      // Decrypt cookie value to get account identifier
      let accountId = null;
      if (chromeKey && encHex) {
        try {
          const encrypted = Buffer.from(encHex, 'hex');
          const decrypted = decryptCookieValue(encrypted, chromeKey);
          if (decrypted) {
            // Skip 32-byte hash prefix for v24+ cookies
            let value = decrypted.length > 32 ?
              decrypted.slice(32).toString('utf8') :
              decrypted.toString('utf8');

            // Extract account info based on cookie type
            if (cookieName === 'dotcom_user') {
              // GitHub: value is the username directly
              accountId = value;
            } else if (cookieName === 'twid') {
              // Twitter: format is "u=1234567890"
              const match = value.match(/u=(\d+)/);
              accountId = match ? `user:${match[1]}` : null;
            } else if (cookieName === 'c_user' || cookieName === 'ds_user_id') {
              // Facebook/Instagram: numeric user ID
              accountId = `user:${value}`;
            } else if (cookieName === 'OSID') {
              // Google services: get email from Chrome Preferences
              const googleEmail = getGoogleEmailFromPreferences(profilePath);
              accountId = googleEmail || '(logged in)';
            } else {
              // Other cookies: just indicate "logged in"
              accountId = '(logged in)';
            }
          }
        } catch (err) {
          // Decryption failed, skip
        }
      }

      if (!accountId) continue;

      // Calculate time ago
      const lastAccess = BigInt(lastAccessStr);
      const secondsAgo = Number((nowChrome - lastAccess) / 1000000n);

      // Add to service accounts
      if (!serviceAccounts[service]) serviceAccounts[service] = [];

      // Check for duplicate accounts
      const existing = serviceAccounts[service].find(a => a.account === accountId);
      if (!existing) {
        serviceAccounts[service].push({
          account: accountId,
          domain,
          timeAgo: formatTimeAgo(secondsAgo),
          secondsAgo
        });
      }
    }

    return serviceAccounts;
  } catch (err) {
    return {};
  }
}

function detectChromeAccounts(profilePath, targetService) {
  const cookiesDb = path.join(profilePath, 'Cookies');
  if (!fs.existsSync(cookiesDb)) return [];

  // Load domain mappings
  const mappingsFile = path.join(SCRIPT_DIR, 'domain-mappings.json');
  let mappings = {};
  if (fs.existsSync(mappingsFile)) {
    mappings = JSON.parse(fs.readFileSync(mappingsFile, 'utf8'));
  }

  // Chrome time epoch: Jan 1, 1601 (microseconds)
  const CHROME_EPOCH_OFFSET = 11644473600000000n;
  const nowChrome = BigInt(Date.now()) * 1000n + CHROME_EPOCH_OFFSET;

  // Query cookies database using sqlite3 CLI
  const query = `
    SELECT DISTINCT host_key, MAX(last_access_utc) as last_access
    FROM cookies
    WHERE expires_utc > ${nowChrome}
      AND last_access_utc > 0
    GROUP BY host_key
    ORDER BY last_access DESC
  `;

  try {
    const result = execSync(`sqlite3 -separator '|' "${cookiesDb}" "${query}"`, {
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'pipe']
    });

    const accounts = [];
    const seenServices = new Set(); // Deduplicate by service, not domain

    for (const line of result.trim().split('\n')) {
      if (!line) continue;
      const [rawDomain, lastAccessStr] = line.split('|');
      const domain = rawDomain.replace(/^\./, '');

      const service = mappings[domain];
      if (targetService && service !== targetService) continue;
      if (!targetService && !service) continue;

      // Only keep first (most recent) entry per service
      if (seenServices.has(service)) continue;
      seenServices.add(service);

      const lastAccess = BigInt(lastAccessStr);
      const secondsAgo = Number((nowChrome - lastAccess) / 1000000n);

      accounts.push({
        domain,
        service: service || 'unknown',
        secondsAgo,
        timeAgo: formatTimeAgo(secondsAgo)
      });
    }

    return accounts;
  } catch (err) {
    return [];
  }
}

// ============================================================================
// Accounts Command - Lists all accounts from Chrome (auto-discovery)
// ============================================================================

function cmdAccounts(showAll = false, filterTerm = null) {
  // Get Chrome encryption key for account detection
  const chromeKey = getBrowserEncryptionKey('chrome');

  if (!chromeKey) {
    console.log('Chrome encryption key not available.\n');
    console.log('Grant Keychain access when prompted, or use --keyless mode.\n');
    return;
  }

  // Get all Chrome profiles
  const chromeProfiles = getAllChromeProfiles();

  if (chromeProfiles.length === 0) {
    console.log('No Chrome profiles found.\n');
    return;
  }

  // Process each profile
  for (const profileName of chromeProfiles) {
    const profilePath = path.join(CHROME_APP_DIR, profileName);

    // Discover all accounts
    const { loggedIn, visited } = discoverAllAccounts(profilePath, chromeKey, showAll);

    // Sort by recency (most recent first)
    loggedIn.sort((a, b) => a.secondsAgo - b.secondsAgo);

    // Apply fuzzy filter if provided
    let filtered = loggedIn;
    if (filterTerm) {
      const term = filterTerm.toLowerCase();
      filtered = loggedIn.filter(entry =>
        entry.service.toLowerCase().includes(term) ||
        entry.domain.toLowerCase().includes(term) ||
        (entry.account && entry.account.toLowerCase().includes(term))
      );
    }

    // Determine display list
    const totalCount = filtered.length;
    const displayLimit = 25;
    const displayList = showAll ? filtered : filtered.slice(0, displayLimit);

    // Print profile header
    console.log(`\nRecent Accounts (Chrome: ${profileName})\n`);

    if (displayList.length === 0) {
      console.log('  No accounts found.\n');
    } else {
      // Calculate column widths
      const maxDomain = Math.max(...displayList.map(e => e.domain.length));

      for (const entry of displayList) {
        const domain = entry.domain.padEnd(maxDomain + 2);
        const account = entry.account || '(active)';
        console.log(`  ${domain}${account}`);
      }
      console.log();
    }

    // Show count summary if not showing all
    if (!showAll && totalCount > displayLimit) {
      console.log(`Showing ${displayLimit} of ${totalCount}. Use --all for complete list.\n`);
    }
  }
}

// Legacy alias for backward compatibility
function cmdProfile() {
  cmdAccounts(false);
}

async function cmdPasswords(filterName = null, showAll = false) {
  const profiles = getAllChromeProfiles();

  for (const profileName of profiles) {
    const profilePath = path.join(CHROME_APP_DIR, profileName);
    const logins = getSavedLogins(profilePath);

    let results = Object.entries(logins)
      .map(([domain, username]) => ({ domain, username }))
      .sort((a, b) => a.domain.localeCompare(b.domain));

    if (filterName) {
      const filter = filterName.toLowerCase();
      results = results.filter(r =>
        r.domain.toLowerCase().includes(filter) ||
        r.username.toLowerCase().includes(filter)
      );
    }

    console.log(`\nSaved Passwords (Chrome: ${profileName})\n`);

    if (results.length === 0) {
      console.log('  No saved passwords found.\n');
      continue;
    }

    const limit = showAll ? results.length : 50;
    const displayList = results.slice(0, limit);
    const maxDomain = Math.min(30, Math.max(...displayList.map(r => r.domain.length)));

    for (const { domain, username } of displayList) {
      console.log(`  ${domain.padEnd(maxDomain)}  ${username}`);
    }
    console.log();

    if (!showAll && results.length > 50) {
      console.log(`Showing 50 of ${results.length}. Use --all for complete list.\n`);
    }
  }
}

// Capitalize first letter
function capitalize(str) {
  if (!str) return str;
  return str.charAt(0).toUpperCase() + str.slice(1);
}

// ============================================================================
// Chrome Login Data - Saved Usernames/Passwords
// ============================================================================

/**
 * Get saved logins from Chrome's Login Data database.
 * Returns a map of registrable domain -> username/email
 *
 * @param {string} profilePath - Path to Chrome profile directory
 * @returns {Object} Map of domain -> username (e.g., { 'github.com': 'myuser' })
 */
function getSavedLogins(profilePath) {
  const loginDataDb = path.join(profilePath, 'Login Data');
  if (!fs.existsSync(loginDataDb)) return {};

  // Chrome locks the database, so we need to copy it first
  const tempDb = `/tmp/login_data_copy_${process.pid}.db`;

  try {
    execSync(`cp "${loginDataDb}" "${tempDb}"`, { stdio: 'pipe' });
  } catch (err) {
    return {};
  }

  // Query for saved logins (we don't need passwords, just usernames)
  const query = `SELECT origin_url, username_value FROM logins WHERE username_value <> '' ORDER BY date_last_used DESC`;

  let result;
  try {
    result = execSync(`sqlite3 -separator '|' "${tempDb}" "${query}"`, {
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'pipe'],
      maxBuffer: 10 * 1024 * 1024
    });
  } catch (err) {
    try { fs.unlinkSync(tempDb); } catch {}
    return {};
  }

  // Clean up temp file
  try { fs.unlinkSync(tempDb); } catch {}

  // Parse results and build domain -> username map
  // Keep most recently used username for each domain
  const domainLogins = {};

  for (const line of result.trim().split('\n')) {
    if (!line) continue;
    const pipeIdx = line.indexOf('|');
    if (pipeIdx === -1) continue;

    const originUrl = line.substring(0, pipeIdx);
    const username = line.substring(pipeIdx + 1);

    if (!username) continue;

    // Extract domain from origin_url
    let domain;
    try {
      const url = new URL(originUrl);
      domain = url.hostname.replace(/^www\./, '');
    } catch {
      continue;
    }

    // Get registrable domain (e.g., 'accounts.google.com' -> 'google.com')
    const registrable = getRegistrableDomain(domain);

    // Only keep first (most recent) username per domain
    if (!domainLogins[registrable]) {
      domainLogins[registrable] = username;
    }
  }

  return domainLogins;
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

  // Helper to truncate long values
  const truncateValue = (val, maxLen = 40) => {
    if (val.length <= maxLen) return `'${val}'`;
    return `'${val.slice(0, maxLen)}...' (${val.length} chars)`;
  };

  const params = data.urlParams || {};
  if (Object.keys(params).length > 0) {
    console.log('Discovered Parameters:');
    console.log('-'.repeat(60));
    for (const [name, info] of Object.entries(params)) {
      const source = info.source || 'unknown';
      const allExamples = info.examples || [];

      // Show first example (truncated if long), then indicate if more exist
      let display;
      if (allExamples.length === 0) {
        display = '(empty)';
      } else if (allExamples.length === 1) {
        display = truncateValue(allExamples[0]);
      } else {
        // Show first value + count of additional values
        display = truncateValue(allExamples[0]);
        if (allExamples.length > 1) {
          display += ` (+${allExamples.length - 1} more)`;
        }
      }

      console.log(`  ${name.padEnd(20)} [${source.padStart(5)}] ${display}`);
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

  // Simplify URL pattern - multi-line if too long
  if (summary.patternUrl) {
    console.log('URL Pattern:');
    console.log('-'.repeat(60));
    const pattern = summary.patternUrl;
    if (pattern.length <= 80) {
      console.log(`  ${pattern}`);
    } else {
      // Extract base URL and params
      const [base, queryString] = pattern.split('?');
      console.log(`  Base: ${base}`);
      if (queryString) {
        const paramNames = queryString.split('&').map(p => p.split('=')[0]);
        // Show first 8 params, then count
        const shown = paramNames.slice(0, 8).join(', ');
        const remaining = paramNames.length - 8;
        if (remaining > 0) {
          console.log(`  Params: ${shown}, ... (+${remaining} more)`);
        } else {
          console.log(`  Params: ${shown}`);
        }
      }
    }
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
  --account SERVICE[:USER]  Use account from Chrome (cookie injection, Chromium)
  --keyless                 Use Chrome Canary with profile copy (no Keychain needed)
  --debug                   Use headed browser (visible window)

COMMANDS:
  open URL                Open URL
  click SELECTOR          Click element (--index N for Nth match)
  input SELECTOR VALUE    Type into field
  sendkey KEY             Send key (enter, esc, tab, arrows)
  snapshot                Page accessibility tree
  selector                List clickable elements with CSS selectors
  account                 Saved accounts
  password                Saved passwords
  execute JS              Run JS in page (last resort)
#   hover SELECTOR        Hover element
#   drag SRC TARGET       Drag element
#   tabs                  List open tabs
#   wait [SELECTOR]       Wait for element
#   screenshot            Capture screenshot
#   close                 Close browser
#   inspect               Discover URL parameters

EXAMPLES:
  browser open "https://google.com"
  browser --account github open "https://github.com"
  browser --account github:myuser open "https://github.com"
  browser --keyless open "https://github.com"
  browser --debug open "https://github.com"
  browser --debug --keyless open "https://github.com"
`);
}

// ============================================================================
// Signal Handlers (cleanup on exit)
// ============================================================================

function cleanup() {
  const sessionName = ACCOUNT || 'default';
  releaseSession(sessionName);
}

process.on('SIGINT', () => {
  cleanup();
  process.exit(130);
});

process.on('SIGTERM', () => {
  cleanup();
  process.exit(143);
});

// ============================================================================
// Main
// ============================================================================

async function main() {
  const args = process.argv.slice(2);

  // Parse global flags
  let i = 0;
  while (i < args.length && args[i].startsWith('--')) {
    if ((args[i] === '--account' || args[i] === '-a') && args[i + 1]) {
      ACCOUNT = args[i + 1];
      const parsed = parseAccount(ACCOUNT);
      ACCOUNT_SERVICE = parsed.service;
      ACCOUNT_USER = parsed.user;
      ACCOUNT_PROFILE = parsed.chromeProfile;
      SESSION_PATH = getSessionPath(ACCOUNT);
      i += 2;
    } else if (args[i] === '--debug') {
      DEBUG_MODE = true;
      i++;
    } else if (args[i] === '--keyless') {
      KEYLESS_MODE = true;
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
      case 'selector':
        await cmdSnapshotSelectors();
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
      case 'account': {
        const showAll = restArgs.includes('--all');
        const filterTerm = restArgs.find(arg => arg && !arg.startsWith('--'));
        cmdAccounts(showAll, filterTerm);
        break;
      }
      case 'password': {
        const showAll = restArgs.includes('--all');
        const filterName = restArgs.find(arg => arg && !arg.startsWith('--'));
        await cmdPasswords(filterName, showAll);
        break;
      }
      case 'profile':
        cmdProfile();
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
