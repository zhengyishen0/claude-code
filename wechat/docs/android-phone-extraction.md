# WeChat Database Extraction from Android Phone

## Overview

This document describes how to extract and decrypt the WeChat message database directly from an Android phone, bypassing the emulator approach.

## Requirements

- **Rooted Android phone** (required for direct file access)
- ADB installed on computer
- Python 3.x with `pycryptodome` package

## Database Location

WeChat stores its encrypted database at:
```
/data/data/com.tencent.mm/MicroMsg/<user_hash>/EnMicroMsg.db
```

Where `<user_hash>` is an MD5 hash of the user's UIN.

## Encryption Scheme

WeChat uses **SQLCipher** encryption with a 7-character key derived from:

```
Key = MD5(IMEI + UIN)[:7]
```

| Component | Description | Location |
|-----------|-------------|----------|
| IMEI | Device identifier (15 digits) | `CompatibleInfo.cfg` or system |
| UIN | WeChat User ID (numeric) | `shared_prefs/auth_info_key_prefs.xml` |

## Extraction Steps

### Step 1: Enable USB Debugging

1. Go to Settings → About Phone
2. Tap "Build Number" 7 times to enable Developer Options
3. Go to Settings → Developer Options → Enable USB Debugging

### Step 2: Connect Phone via ADB

```bash
adb devices
# Should show your device
```

### Step 3: Get Root Access

```bash
adb root
# Or if using su:
adb shell
su
```

### Step 4: Find User Hash

```bash
adb shell ls /data/data/com.tencent.mm/MicroMsg/
# Look for 32-character hex folder (not "avatar", "crash", etc.)
# Example: a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6
```

### Step 5: Extract Database

```bash
USER_HASH="a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6"  # Replace with actual

adb pull /data/data/com.tencent.mm/MicroMsg/${USER_HASH}/EnMicroMsg.db ./
```

### Step 6: Extract Key Material

```bash
# Get UIN from shared_prefs
adb pull /data/data/com.tencent.mm/shared_prefs/auth_info_key_prefs.xml ./

# Get IMEI from CompatibleInfo.cfg (if available)
adb pull /data/data/com.tencent.mm/MicroMsg/${USER_HASH}/CompatibleInfo.cfg ./
```

### Step 7: Derive Decryption Key

Parse the extracted files to get IMEI and UIN:

```python
import hashlib
import xml.etree.ElementTree as ET

# Parse UIN from XML
tree = ET.parse('auth_info_key_prefs.xml')
uin = tree.find('.//int[@name="_auth_uin"]').get('value')

# IMEI: either from CompatibleInfo.cfg or device
# CompatibleInfo.cfg stores it at offset 0x14 (20 bytes in)
with open('CompatibleInfo.cfg', 'rb') as f:
    data = f.read()
    # IMEI is typically at a known offset, varies by version
    imei = extract_imei(data)  # Implementation varies

# Derive key
key_source = imei + uin
key = hashlib.md5(key_source.encode()).hexdigest()[:7]
print(f"Decryption key: {key}")
```

### Step 8: Decrypt Database

```python
from pysqlcipher3 import dbapi2 as sqlite

conn = sqlite.connect('EnMicroMsg.db')
conn.execute(f"PRAGMA key = '{key}';")
conn.execute("PRAGMA cipher_compatibility = 3;")

# Test decryption
cursor = conn.execute("SELECT name FROM sqlite_master WHERE type='table';")
tables = cursor.fetchall()
print(f"Tables: {tables}")
```

## Alternative: IMEI Sources

If `CompatibleInfo.cfg` doesn't contain IMEI:

1. **From phone dialer**: Dial `*#06#`
2. **From system**: `adb shell service call iphonesubinfo 1` (may need root)
3. **From WeChat logs**: Check `/data/data/com.tencent.mm/MicroMsg/systemInfo.cfg`

## Troubleshooting

### "file is not a database" error
- Wrong key - verify IMEI and UIN
- Try different cipher compatibility modes (1, 2, 3, 4)

### Multiple user folders
- Multiple WeChat accounts = multiple folders
- Check `account_info.xml` for account details

### IMEI format issues
- Some phones use MEID instead of IMEI
- Virtual/dual-SIM phones may have different identifiers
- WeChat might use a "fake" IMEI it generated

## Non-Rooted Alternatives

Without root access, options are limited:

| Method | Feasibility | Notes |
|--------|-------------|-------|
| ADB backup | Low | Deprecated Android 12+, WeChat may block |
| WeChat PC sync | Medium | Different encryption, limited data |
| Emulator approach | High | Universal, covered in main docs |
| Manufacturer backup | Low | Proprietary encrypted format |

## Security Notes

- The database contains personal messages - handle securely
- Keys are device-specific - database can't be decrypted on another device without the key
- This is for personal data recovery only

## Future Work

- [ ] Automate IMEI extraction from various sources
- [ ] Handle different WeChat versions
- [ ] Support iOS extraction (different approach needed)
- [ ] GUI tool for beginners
