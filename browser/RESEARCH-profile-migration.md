# Chrome Profile Migration Research

## Executive Summary

This document explores methods for migrating browser credentials/sessions between Chrome variants (Chrome, Chromium, Chrome Canary) with fine-grained control over which services are accessible.

**Key Findings:**
1. ✅ Full profile copy works between Chrome variants sharing the same Keychain
2. ✅ Per-service cookie extraction + CDP injection works for fine-grained control
3. ❌ Database re-encryption does not work (browsers ignore modified databases)

---

## Part 1: Chrome Storage Architecture

### Cookie Database Schema

Chrome stores cookies in SQLite at `~/Library/Application Support/Google/Chrome/Default/Cookies`

```sql
CREATE TABLE cookies (
  creation_utc INTEGER NOT NULL,       -- microseconds since epoch
  host_key TEXT NOT NULL,              -- domain (e.g., ".github.com")
  name TEXT NOT NULL,                  -- cookie name
  value TEXT NOT NULL,                 -- plaintext value (legacy)
  path TEXT NOT NULL,                  -- cookie path
  expires_utc INTEGER NOT NULL,        -- expiration time
  is_secure INTEGER NOT NULL,          -- 1 = HTTPS only
  is_httponly INTEGER NOT NULL,        -- 1 = no JS access
  last_access_utc INTEGER NOT NULL,    -- last read time
  has_expires INTEGER NOT NULL DEFAULT 1,
  is_persistent INTEGER NOT NULL DEFAULT 1,
  priority INTEGER NOT NULL DEFAULT 1,
  encrypted_value BLOB DEFAULT '',     -- encrypted value (modern)
  samesite INTEGER NOT NULL DEFAULT -1,-- -1=unset, 0=None, 1=Lax, 2=Strict
  source_scheme INTEGER NOT NULL DEFAULT 0,
  UNIQUE (host_key, name, path)
)
```

### Cookie Encryption (macOS)

| Component | Value |
|-----------|-------|
| Algorithm | AES-128-CBC |
| Key Source | macOS Keychain ("Chrome Safe Storage") |
| Key Derivation | PBKDF2(password, "saltysalt", 1003, 16, SHA1) |
| IV | 16 space characters (0x20) |
| Format | "v10" prefix + ciphertext |
| Version 24+ | 32-byte SHA256(host_key) prefix before actual value |

### Keychain Entry Sharing

| Browser | Keychain Service Name | Shares With |
|---------|----------------------|-------------|
| Chrome Stable | Chrome Safe Storage | Beta, Dev, Canary |
| Chrome Beta | Chrome Safe Storage | Stable, Dev, Canary |
| Chrome Dev | Chrome Safe Storage | Stable, Beta, Canary |
| Chrome Canary | Chrome Safe Storage | Stable, Beta, Dev |
| Chromium | Chromium Safe Storage | None |
| Brave | Brave Safe Storage | None |
| Vivaldi | Vivaldi Safe Storage | None |

### Other Data Storage

| Data Type | Location | Notes |
|-----------|----------|-------|
| Cookies | `Default/Cookies` | SQLite, encrypted |
| Passwords | `Default/Login Data` | SQLite, encrypted |
| Local Storage | `Default/Local Storage/leveldb/` | Per-origin |
| IndexedDB | `Default/IndexedDB/` | Per-origin |
| Session Storage | Memory only | Lost on close |
| Cache | `Default/Cache/` | HTTP cache |

---

## Part 2: Migration Methods

### Method 1: Full Profile Copy ✅ VERIFIED

**Best for:** Same-Keychain browsers (Chrome → Chrome Canary/Beta/Dev)

**Process:**
```bash
# Close target browser
pkill -f "Google Chrome Canary"

# Copy profile
cp -r "/Library/Application Support/Google/Chrome/Default" \
      "/Library/Application Support/Google/Chrome Canary/Default"

# Open target browser
open -a "Google Chrome Canary"
```

**Test Results:**
| Service | Status | Notes |
|---------|--------|-------|
| GitHub | ✅ Success | Settings page accessible |
| LinkedIn | ✅ Success | Feed with notifications |
| Amazon | ✅ Success | Order history accessible |
| Gmail | ✅ Success | Inbox with emails |

**Pros:**
- Complete session state (cookies, localStorage, IndexedDB)
- No decryption needed
- Simple implementation

**Cons:**
- All-or-nothing (all services copied)
- Large data transfer (can be GBs)
- Only works for same-Keychain browsers

---

### Method 2: Per-Service Cookie Extraction + CDP Injection ✅ VERIFIED

**Best for:** Fine-grained service selection, any Chromium browser

**Process:**
1. Extract cookies from Chrome's SQLite database
2. Decrypt using Keychain key
3. Filter by service domain
4. Start target browser with fresh profile
5. Clear existing cookies via CDP
6. Inject cookies via `Network.setCookie()`

**Implementation:**
```javascript
// Extract only GitHub cookies
const query = `
  SELECT host_key, name, path, is_secure, is_httponly,
         samesite, hex(encrypted_value)
  FROM cookies
  WHERE host_key LIKE '%github.com%'
    AND length(encrypted_value) > 0
`;

// Inject via CDP
await Network.setCookie({
  name: cookie.name,
  value: cookie.value,
  domain: cookie.domain,
  path: cookie.path,
  secure: cookie.secure,
  httpOnly: cookie.httpOnly,
  sameSite: cookie.sameSite
});
```

**Special Handling for `__Host-` Cookies:**
```javascript
// __Host- prefix requires url instead of domain
if (cookie.name.startsWith('__Host-')) {
  params.url = `https://${domain}/`;
  // Don't set domain property
} else {
  params.domain = cookie.domain;
}
```

**Test Results:**
| Service | Status | Cookies | Notes |
|---------|--------|---------|-------|
| GitHub | ✅ Success | 13 | user_session, logged_in |
| LinkedIn | ✅ Success | ~20 | li_at, JSESSIONID |
| Gmail | ✅ Success | ~30 | SID, HSID, SSID |
| Amazon | 🔬 Untested | - | - |

**Pros:**
- Fine-grained service selection
- Small data footprint (KB instead of GB)
- Works with any Chromium browser
- Per-service isolation

**Cons:**
- Cookies only (no localStorage/IndexedDB)
- Session may be shorter-lived
- Requires CDP connection

---

### Method 3: Profile Copy + Selective Deletion ⚠️ POSSIBLE

**Best for:** When you need localStorage/IndexedDB but want fewer services

**Process:**
```bash
# Copy full profile
cp -r "Chrome/Default" "Chrome Canary/Default"

# Delete unwanted cookies
sqlite3 "Chrome Canary/Default/Cookies" \
  "DELETE FROM cookies WHERE host_key NOT LIKE '%github%'"

# Delete unwanted localStorage (careful with leveldb!)
rm -rf "Chrome Canary/Default/Local Storage/leveldb/https_unwanted.com_*"
```

**Caution:** LevelDB deletion is complex - may corrupt database.

---

### Method 4: Database Re-encryption ❌ DOES NOT WORK

**Why it fails:**
- Browser validates database integrity on startup
- Session tokens may be invalidated server-side
- Browser may use in-memory cookie store instead of reading from disk

---

## Part 3: Service-by-Service Cookie Analysis

### GitHub
```
Required cookies:
- user_session (session token)
- __Host-user_session_same_site (same-site session)
- logged_in (login status flag)
- dotcom_user (username)
- _gh_sess (session data)

Optional:
- color_mode (theme preference)
- tz (timezone)
- cpu_bucket (performance bucket)
```

### Google/Gmail
```
Required cookies:
- SID (session ID)
- HSID (HTTP-only session)
- SSID (secure session)
- APISID (API session)
- SAPISID (secure API session)
- OSID (per-account session)

Multi-account:
- All accounts share the same cookies
- Account selection via URL (/mail/u/0/, /mail/u/1/)
```

### LinkedIn
```
Required cookies:
- li_at (access token)
- JSESSIONID (session ID)
- li_rm (remember me)
- lidc (LinkedIn data center)
```

### Amazon
```
Required cookies:
- session-id (session identifier)
- session-id-time (session timestamp)
- x-main (main authentication)
- at-main (auth token)
- sess-at-main (session auth)
```

---

## Part 4: Fine-Grained Access Control

### Option A: Domain-Based Filtering ✅ IMPLEMENTED
```javascript
// domain-mappings.json
{
  "github.com": "github",
  "www.github.com": "github",
  "mail.google.com": "gmail",
  "accounts.google.com": "gmail"
}

// Extract only specified service
const cookies = extractChromeCookies(cookiesDb, chromeKey, "github");
```

**Granularity:** Service-level (all GitHub, all Google, etc.)

### Option B: Cookie Name Filtering 🔬 POSSIBLE
```javascript
// Session cookies only
const sessionCookies = cookies.filter(c =>
  ['user_session', 'li_at', 'SID'].includes(c.name)
);

// Exclude tracking cookies
const cleaned = cookies.filter(c =>
  !c.name.includes('_ga') && !c.name.includes('_fbp')
);
```

**Granularity:** Can separate auth from tracking/analytics

### Option C: Per-Service Profiles ✅ IMPLEMENTED
```
profiles/
├── github-work/
│   └── .cookies.json      # Only github.com cookies
├── gmail-personal/
│   └── .cookies.json      # Only google.com cookies
├── amazon-shopping/
│   └── .cookies.json      # Only amazon.com cookies
└── linkedin-professional/
    └── .cookies.json      # Only linkedin.com cookies
```

**Granularity:** Complete isolation per service

---

## Part 5: Browser Comparison

| Feature | Chrome | Chrome Canary | Chromium | Brave |
|---------|--------|---------------|----------|-------|
| Profile Copy | ✅ Works | ✅ Works (same key) | ❌ Different key | ❌ Different key |
| CDP Injection | ✅ Works | ✅ Works | ✅ Works | ✅ Works |
| Headless Mode | ✅ Works | ✅ Works | ✅ Works | ✅ Works |
| Same Keychain | ✅ Chrome | ✅ Chrome | ❌ Chromium | ❌ Brave |

---

## Part 6: Production Implementation

### Recommended Approach

1. **For Same-Keychain browsers (Chrome → Chrome Canary):**
   - Use full profile copy for complete session state
   - Fast and simple

2. **For Different-Keychain browsers (Chrome → Chromium):**
   - Use CDP cookie injection
   - Extract, decrypt, inject per-service

3. **For Fine-Grained Control:**
   - Use CDP injection with domain filtering
   - Create per-service profiles
   - Inject only needed cookies

### CLI Usage

```bash
# Import service from Chrome
browser profile github 1 work-account

# Use profile
browser --profile github-work_account open "https://github.com"

# List available services
browser profile
```

---

## Part 7: Security Considerations

### Cookie Theft Protection
- Cookies are encrypted at rest
- Keychain requires user authentication
- CDP injection requires local access

### Session Token Rotation
- Services may rotate session tokens
- Re-extract cookies periodically
- Some tokens expire regardless of activity

### Privacy Implications
- Cookie extraction bypasses normal auth flow
- Cookies can be exported to other machines
- Consider organizational security policies

---

## Sources

- [Chrome Cookie Encryption Format](https://gist.github.com/creachadair/937179894a24571ce9860e2475a2d2ec)
- [Chromium CookieMonster Design](https://www.chromium.org/developers/design-documents/network-stack/cookiemonster/)
- [Chrome Cookies README](https://chromium.googlesource.com/chromium/src/+/HEAD/net/cookies/README.md)
- [CHIPS Privacy Sandbox](https://privacysandbox.google.com/cookies/chips)
- [Current State of Browser Cookies (CyberArk)](https://www.cyberark.com/resources/threat-research-blog/the-current-state-of-browser-cookies)

---

*Last updated: 2025-01-13*
