# Chrome Profile & Credential Strategy

## Overview

Cookie-based authentication for headless Chrome automation with cloud deployment support.

## Key Principle

**Use session cookies only** - No reliance on saved passwords (macOS Keychain-encrypted, not portable).

## Profile Structure

```
~/.claude/chrome/profiles/
├── personal/
│   ├── Default/
│   │   ├── Cookies              (52KB)  ← Session tokens (PORTABLE ✅)
│   │   ├── Login Data           (1.4MB) ← Saved passwords (NOT portable ❌)
│   │   ├── Preferences          (34KB)  ← Settings (portable)
│   │   ├── History              (18MB)  ← Optional
│   │   └── ...
│   └── .gitignore
└── work/
    └── Default/
        └── ...
```

## How Chrome Profiles Work

### What Gets Saved

1. **Session Cookies** (PORTABLE ✅)
   - Stored in SQLite database: `Default/Cookies`
   - Contains session tokens for logged-in websites
   - Works across machines (no encryption tied to OS)
   - **This is what we rely on**

2. **Saved Passwords** (NOT PORTABLE ❌)
   - Stored in: `Default/Login Data`
   - Encrypted using macOS Keychain (machine-specific)
   - Won't work when copied to different machine
   - **We don't use this**

3. **Preferences** (PORTABLE ✅)
   - Browser settings, extensions, etc.
   - JSON files, portable across machines

4. **History** (PORTABLE ✅)
   - SQLite database
   - Optional for AI agent use cases

### Auto-Save Behavior

Chrome continuously saves profile data:
- Cookies saved immediately after each HTTP response
- No manual save needed
- No browser close required
- Profile is always ready for use

## Profile Setup Workflow

### Local Machine Setup

```bash
# 1. Create profile by opening Chrome in headed mode
chrome-cli profile personal https://gmail.com

# 2. User logs in manually in the browser window
# (Chrome auto-saves cookies as you login)

# 3. Close browser when done
# Profile is now ready for headless use

# 4. Test profile works in headless mode
chrome-cli open --profile personal https://gmail.com
```

### Cloud Deployment

```bash
# 1. Create profile locally (see above)

# 2. Transfer profile to cloud
rsync -av ~/.claude/chrome/profiles/personal/ cloud:/profiles/personal/

# 3. Launch Chrome on cloud with same profile
google-chrome \
  --headless=new \
  --user-data-dir=/profiles/personal \
  --remote-debugging-port=9222

# 4. Sites stay logged in via cookies
```

## Testing Evidence

**Gmail Test (2025-12-17):**
- Created profile with Gmail login
- Killed Chrome completely
- Restarted Chrome with same profile
- Result: Still logged in
  - Page title: "Inbox - zhengyishen1@gmail.com - Gmail"
  - Content: 466KB inbox HTML
  - **Conclusion: Cookies persist credentials successfully**

**Airbnb Test:**
- Similar results
- Full page loaded (1.19MB)
- All listings visible
- No re-authentication needed

## Multi-User Support

Each user gets isolated profile:

```bash
# User 1
chrome --user-data-dir=/profiles/user1 --remote-debugging-port=9222

# User 2
chrome --user-data-dir=/profiles/user2 --remote-debugging-port=9223

# User 3
chrome --user-data-dir=/profiles/user3 --remote-debugging-port=9224
```

**Key points:**
- One Chrome instance per profile
- Different CDP port for each instance
- Complete isolation (no shared cookies)

## Security Considerations

### Profile Data Sensitivity

Profiles contain **active session tokens** = full account access

Treat profile directories as sensitive as:
- API keys
- Database credentials
- Private keys

### Security Measures

1. **File Permissions**
   ```bash
   chmod 700 ~/.claude/chrome/profiles
   chmod 700 ~/.claude/chrome/profiles/*/
   ```

2. **Cloud Storage**
   - Use encrypted volumes (LUKS, dm-crypt)
   - Encrypt during transfer (rsync over SSH)
   - Never commit to git

3. **Transfer Security**
   ```bash
   # Good: Encrypted transfer
   rsync -av -e "ssh -i ~/.ssh/key" profiles/ user@cloud:/profiles/

   # Bad: Unencrypted
   scp -r profiles/ cloud:/profiles/  # Still encrypted by SSH, but be explicit
   ```

4. **Cookie Rotation**
   - Re-login periodically (every 30-90 days)
   - Websites may expire cookies
   - Refresh profile by running headed mode login again

5. **Access Control**
   - Each user should have separate OS user (ideal)
   - Or at minimum, file permissions preventing cross-access
   - Never share profiles between users

### .gitignore for Profiles

```gitignore
# Profile data contains session cookies
profiles/*/Default/
profiles/*/SingletonCookie
profiles/*/SingletonLock
profiles/*/SingletonSocket

# Keep profile structure
!profiles/*/.gitignore
```

## Advantages of Cookie-Based Auth

1. **Portable** - Works across machines
2. **No password storage** - More secure (no keychain dependency)
3. **Fast** - No login UI automation needed
4. **Simple** - Just copy files
5. **Cloud-ready** - Designed for this use case

## Limitations

1. **Initial login required** - Must use headed mode once
2. **Cookie expiration** - Websites may expire sessions (days to months)
3. **IP changes** - Some sites may challenge on IP change
4. **2FA** - May need to approve new device
5. **Bot detection** - Still subject to anti-automation (but using real Chrome helps)

## Best Practices

1. **Create profiles locally** - Use headed mode for initial login
2. **Test before cloud sync** - Verify profile works headless locally
3. **Document profile purpose** - What sites/accounts are logged in
4. **Regular updates** - Re-login if sessions expire
5. **Monitor failures** - Log CDP errors for session expiration detection

## Profile Lifecycle

```
1. CREATE (local, headed mode)
   └─> User logs into websites manually
   └─> Chrome saves cookies automatically

2. TEST (local, headless mode)
   └─> Verify sites stay logged in
   └─> Confirm profile works without browser UI

3. SYNC (rsync to cloud)
   └─> Transfer entire profile directory
   └─> Encrypted transfer over SSH

4. USE (cloud, headless mode)
   └─> Launch Chrome with profile path
   └─> CDP automation for browser control
   └─> Sites remain logged in via cookies

5. MAINTAIN (periodic re-login)
   └─> Watch for session expiration
   └─> Re-run CREATE step when needed
   └─> Re-sync to cloud
```

## Troubleshooting

### Profile not working after transfer

**Symptom:** Sites ask for login on cloud
**Causes:**
1. Cookies expired (time-based)
2. Different Chrome version
3. Profile corruption during transfer

**Solutions:**
1. Check file integrity: `md5sum Cookies` before/after transfer
2. Verify Chrome version matches (local and cloud)
3. Re-create profile if corrupted

### Session expired

**Symptom:** Login page appears
**Solution:** Re-run profile setup (headed mode login)

### Multiple profiles interfering

**Symptom:** Wrong user logged in
**Cause:** Profile paths mixed up
**Solution:** Use absolute paths, verify `--user-data-dir`

## Example Commands

```bash
# Create new profile (headed)
chrome-cli profile personal https://gmail.com

# Use profile (headless)
chrome-cli open --profile personal https://gmail.com/mail/u/0/#inbox

# Sync to cloud
rsync -av ~/.claude/chrome/profiles/personal/ cloud:/profiles/personal/

# Cloud usage
google-chrome \
  --headless=new \
  --user-data-dir=/profiles/personal \
  --remote-debugging-port=9222 \
  &

# CDP automation (after Chrome launched)
node cdp-cli.js open "https://example.com"
```
