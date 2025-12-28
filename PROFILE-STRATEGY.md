# Chrome Profile Security & Best Practices

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
