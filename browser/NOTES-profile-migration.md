# Profile Migration Notes

## Summary

Two verified working approaches for credential migration:

### 1. Full Profile Copy (Chrome → Chrome Canary)
- **Works because**: All Chrome variants share "Chrome Safe Storage" Keychain
- **Command**: `cp -r "Chrome/Default" "Chrome Canary/Default"`
- **Tested**: GitHub ✅, Gmail ✅, LinkedIn ✅, Amazon ✅

### 2. Per-Service CDP Injection (Any Chromium browser)
- **Works because**: CDP can inject cookies directly into browser memory
- **Command**: `browser profile github 1 account-name`
- **Tested**: GitHub ✅, Gmail ✅, LinkedIn ✅, Amazon ✅

---

## Chrome Cookie Encryption (macOS)

| Component | Value |
|-----------|-------|
| Algorithm | AES-128-CBC |
| Key Source | Keychain "Chrome Safe Storage" |
| Key Derivation | PBKDF2(password, "saltysalt", 1003, 16, SHA1) |
| IV | 16 space characters (0x20) |
| Format | "v10" prefix + ciphertext |
| V24+ | 32-byte SHA256 hash prefix before value |

---

## Keychain Sharing

```
Chrome Stable  ─┐
Chrome Beta    ─┼─ "Chrome Safe Storage" (shared key)
Chrome Dev     ─┤
Chrome Canary  ─┘

Chromium ────────── "Chromium Safe Storage" (separate)
Brave ───────────── "Brave Safe Storage" (separate)
```

---

## CLI Usage

```bash
# List available services in Chrome
browser profile

# Import service from Chrome
browser profile <service> <selection> <account>
browser profile github 1 work

# Use profile
browser --profile github-work open "https://github.com"
browser --profile github-work --debug open "https://github.com"
```

---

## Key Bug Fixed

**Profile path resolution**: `expandProfilePath` now checks for exact profile name before normalizing:
```javascript
function expandProfilePath(profile) {
  // First check if exact profile name exists
  const exactPath = path.join(PROFILES_DIR, profile);
  if (fs.existsSync(exactPath)) {
    return exactPath;
  }
  // Fall back to normalized name
  return path.join(PROFILES_DIR, normalizeProfileName(profile));
}
```

---

## Special Cookie Handling

### `__Host-` Prefix Cookies
```javascript
// Must use url, not domain
if (cookie.name.startsWith('__Host-')) {
  params.url = `https://${domain}/`;
  // Don't set params.domain
}
```

---

## Recommendation

For the browser tool:
1. Use **Chrome Canary** as the automation browser (same Keychain as Chrome)
2. Use **CDP injection** for per-service profiles (fine-grained control)
3. Fall back to **full profile copy** if complete state needed

---

*Last updated: 2025-01-13*
