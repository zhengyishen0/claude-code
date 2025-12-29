# Chrome Profile Security & Best Practices

## Profile Design for AI Agents

### Profile Granularity: Account-Level (Recommended)

Each profile should represent a **single account on a single service**, not a user or scenario.

**✅ Good (Account-Level):**
```
gmail-alice@gmail.com              # Or renamed to: gmail-personal
gmail-alice@company.com            # Or renamed to: gmail-work
github-bot@company.com             # Or renamed to: github-company-bot
amazon-testbuyer1@gmail.com        # Or renamed to: amazon-buyer-1
amazon-testbuyer2@gmail.com        # Or renamed to: amazon-buyer-2
shopify-admin@test.com             # Or renamed to: shopify-admin-test
```

**❌ Avoid (User-Level):**
```
alice    # Too broad - can't handle multiple Gmail accounts
bob      # Too broad - no service isolation
```

**❌ Avoid (Scenario-Level):**
```
work     # What if you need multiple Gmail accounts for work?
personal # Same problem - multiple accounts per service
```

**Why account-level?**
- Maximum flexibility - each login is isolated
- No naming conflicts between services
- Clear mapping: one profile = one account = one set of credentials

### Profile Naming Convention

**Format:** `<app/domain>-<login-identifier>`

One profile = one account on one service. By default, use the actual login credential (email/username/phone).

**Default naming (recommended):**
```bash
# Use the actual login identifier
profile gmail-alice@gmail.com https://gmail.com
profile gmail-work@company.com https://gmail.com
profile amazon-alice@gmail.com https://amazon.com
profile github-alice123 https://github.com
profile shopify-+1234567890 https://shopify.com
```

**Why use actual login identifier?**
- Unambiguous - you know exactly which account
- No confusion with multiple accounts on same service
- Easy to remember which credentials to use

**Rename for convenience (optional):**
```bash
# Rename to friendly names after creation
profile rename gmail-alice@gmail.com gmail-personal
profile rename gmail-work@company.com gmail-work
profile rename amazon-alice@gmail.com amazon-alice

# Use the friendly name
chrome --profile gmail-personal open "https://gmail.com"
```

**Guidelines:**
- Service/domain comes first (for grouping and clarity)
- Login identifier second (email, username, or phone)
- Automatic normalization: lowercase, spaces→underscores, special chars removed
- Rename to friendly names if desired (keeps profiles organized)

### Multi-Agent Concurrent Access

**Profile locking prevents conflicts between AI agents.**

Profiles are automatically locked when in use. Only one agent/session can use a profile at a time.

**Problem without locking:**
```bash
# Agent A: Shopping for laptop
chrome --profile amazon-personal ...
# Adds laptop to cart on Amazon's servers

# Agent B: Shopping for book (parallel!)
chrome --profile amazon-personal ...
# Sees laptop in cart, thinks "error, I should only have book"
# Removes laptop from cart

# Agent A: Goes to checkout
# Laptop is gone! Task failed!
```

**Solution: Profile locking (automatic)**
```bash
# Agent A starts first
chrome --profile amazon-personal open "https://amazon.com"
# ✓ Profile locked

# Agent B tries to use same profile
chrome --profile amazon-personal open "https://amazon.com"
# ✗ ERROR: Profile 'amazon-personal' is already in use
#
#   Details:
#     Process ID: 12345
#     CDP Port: 9222
#     Running for: 5m 23s
```

**For parallel work: Use separate accounts**
```bash
# Setup: Create multiple test accounts (different Amazon accounts!)
profile amazon-buyer1@test.com https://amazon.com
profile amazon-buyer2@test.com https://amazon.com
profile amazon-buyer3@test.com https://amazon.com

# Optional: Rename for convenience
profile rename amazon-buyer1@test.com amazon-buyer-1
profile rename amazon-buyer2@test.com amazon-buyer-2
profile rename amazon-buyer3@test.com amazon-buyer-3

# Use: Each agent gets dedicated account
chrome --profile amazon-buyer-1 ...  # Agent 1 (no conflicts)
chrome --profile amazon-buyer-2 ...  # Agent 2 (no conflicts)
chrome --profile amazon-buyer-3 ...  # Agent 3 (no conflicts)
```

**Important:** If you only have ONE Amazon account, you CANNOT run parallel agents on it. Profile locking prevents this. You must create additional test accounts.

### Why AI Agents Can't Share Accounts

**AI agents lack coordination capabilities:**
- No shared memory across agents
- No inter-agent communication
- No awareness of other agents' tasks
- Can't "wait politely" or "check if cart has my items"

**Shared server-side state causes chaos:**
- Same shopping cart
- Same order history
- Same session state
- Same preferences

**Result:** Agents interfere with each other's work, leading to task failures.

**Design principle:** Prevent conflicts at the tool level (profile locking), don't rely on AI coordination.

### Port Assignment

Each profile automatically gets a unique CDP port (9222-9299 range):
- Ports are assigned based on profile name hash
- Registry tracks active profiles: `~/.claude/chrome/port-registry`
- Automatic cleanup when Chrome exits
- Supports up to 78 concurrent profiles

**Port registry format:**
```
profile-name:port:pid:start-time
amazon-buyer-1:9222:12345:1704067200
amazon-buyer-2:9223:12346:1704067210
gmail-work:9224:12347:1704067220
```

## Security Considerations

### Profile Data = Active Sessions

Profiles contain **active session cookies** that provide full account access. Treat profile directories with the same security as:
- API keys
- Database credentials
- Private keys

### Security Measures

**1. File Permissions**
```bash
chmod 700 ~/.claude/chrome/profiles
chmod 700 ~/.claude/chrome/profiles/*/
```

**2. Cloud Storage**
- Use encrypted volumes (LUKS, dm-crypt)
- Encrypt during transfer (rsync over SSH)
- Never commit to git

**3. Transfer Security**
```bash
# Good: Encrypted transfer
rsync -av -e "ssh -i ~/.ssh/key" profiles/ user@cloud:/profiles/

# Verify integrity after transfer
md5sum ~/.claude/profiles/personal/Default/Cookies
ssh cloud "md5sum /profiles/personal/Default/Cookies"
```

**4. Cookie Rotation**
- Re-login periodically (every 30-90 days)
- Websites may expire cookies
- Refresh profile by running headed mode login again

**5. Access Control**
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

## Multi-User Support

Each user gets isolated profile with separate Chrome instance:

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

## Cloud Deployment

### Transfer Workflow

```bash
# 1. Create profile locally (headed mode for login)
claude-tools chrome profile personal https://gmail.com

# 2. Test locally (headless mode)
claude-tools chrome --profile personal open https://gmail.com

# 3. Transfer to cloud
rsync -av ~/.claude/chrome/profiles/personal/ cloud:/profiles/personal/

# 4. Launch Chrome on cloud with same profile
google-chrome \
  --headless=new \
  --user-data-dir=/profiles/personal \
  --remote-debugging-port=9222
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

## Profile Structure

Understanding what's portable:

```
~/.claude/chrome/profiles/personal/
├── Default/
│   ├── Cookies              (52KB)  ← Session tokens (PORTABLE ✅)
│   ├── Login Data           (1.4MB) ← Saved passwords (NOT portable ❌)
│   ├── Preferences          (34KB)  ← Settings (portable)
│   └── History              (18MB)  ← Optional
```

**Why Login Data isn't portable:**
- Encrypted using macOS Keychain (machine-specific)
- Won't work when copied to different machine
- This is why we rely on cookies only

## Limitations

1. **Initial login required** - Must use headed mode once
2. **Cookie expiration** - Websites may expire sessions (days to months)
3. **IP changes** - Some sites may challenge on IP change
4. **2FA** - May need to approve new device
5. **Bot detection** - Still subject to anti-automation (but using real Chrome helps)
