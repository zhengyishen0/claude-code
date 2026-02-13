# Stealth AVD Setup for WeChat

This document explains how to set up an Android Virtual Device (AVD) with anti-detection measures for running WeChat.

## Overview

The setup creates a rooted AVD that hides its emulator signatures from WeChat's detection:

```
┌─────────────────────────────────────────────────────────────┐
│                    STEALTH AVD STACK                         │
├─────────────────────────────────────────────────────────────┤
│  WeChat (com.tencent.mm)                                    │
│    ↓ sees "Pixel Tablet", no root, no emulator              │
├─────────────────────────────────────────────────────────────┤
│  Shamiko (root hiding from DenyList apps)                   │
│  DeviceSpoof (props: Pixel Tablet, ro.kernel.qemu=0)        │
├─────────────────────────────────────────────────────────────┤
│  Magisk + Zygisk (systemless root)                          │
├─────────────────────────────────────────────────────────────┤
│  Android 35 (google_apis, arm64-v8a)                        │
├─────────────────────────────────────────────────────────────┤
│  QEMU Emulator (AVD)                                        │
└─────────────────────────────────────────────────────────────┘
```

## Quick Start

```bash
# Full automated setup
./bin/setup-avd all

# Or step by step:
./bin/setup-avd download    # Get tools
./bin/setup-avd create      # Create AVD
./bin/setup-avd root        # Install Magisk
./bin/setup-avd stealth     # Add anti-detection
./bin/setup-avd wechat      # Install WeChat
```

## Snapshot Strategy

The setup creates snapshots at each stage for easy recovery:

| # | Snapshot Name | State | Use Case |
|---|---------------|-------|----------|
| 1 | `01_clean_boot` | Fresh Android, no mods | Start over from scratch |
| 2 | `02_magisk_rooted` | Magisk + Zygisk enabled | Re-apply stealth modules |
| 3 | `03_anti_detection` | Shamiko + spoofing active | Re-install WeChat |
| 4 | `04_wechat_installed` | WeChat ready for login | Fresh login attempt |
| - | `wechat_ready` | Logged in, production | Daily use |

Restore any snapshot:
```bash
./bin/setup-avd restore 3    # Restore to anti-detection stage
./bin/setup-avd restore wechat_ready   # Restore production
```

## What Gets Installed

### 1. Magisk (Root)

- **Why**: Required to install Zygisk modules (Shamiko, spoofing)
- **Detection bypassed**: None directly, but enables other protections
- **Installed via**: [rootAVD](https://github.com/newbit1/rootAVD)

### 2. Zygisk

- **Why**: Process injection framework, required by Shamiko
- **Detection bypassed**: Enables hiding root per-app
- **Enabled in**: Magisk settings

### 3. Shamiko Module

- **Why**: Hides root from apps on DenyList
- **Detection bypassed**:
  - `/system/bin/su` file check
  - Magisk app detection
  - Root management app detection
  - `su` command availability

### 4. DeviceSpoof Module

Custom Magisk module that spoofs device properties:

| Property | Real AVD Value | Spoofed Value |
|----------|---------------|---------------|
| `ro.product.model` | `sdk_gphone64_arm64` | `Pixel Tablet` |
| `ro.product.device` | `generic` | `tangorpro` |
| `ro.hardware` | `ranchu` | `tangorpro` |
| `ro.kernel.qemu` | `1` | `0` |
| `ro.build.fingerprint` | `google/sdk_...` | `google/tangorpro/...` |
| `ro.build.characteristics` | `default` | `tablet` |

### 5. Frida Server (Stealth)

- **Renamed**: `frida-server` → `hluda-server`
- **Port**: 31337 (not default 27042)
- **Detection bypassed**:
  - Port 27042/27043 scanning
  - Process name "frida" detection
  - File path `/data/local/tmp/frida-server`

### 6. Battery Spoofing

- **Temperature**: Randomized 28-35°C (not constant 25°C)
- **Level**: Randomized 65-95%
- **Status**: Unplugged (not always charging)

## Detection Points Addressed

| Detection Method | Solution | Status |
|-----------------|----------|--------|
| `ro.kernel.qemu=1` | DeviceSpoof sets to 0 | ✅ |
| `ro.hardware=ranchu/goldfish` | DeviceSpoof: `tangorpro` | ✅ |
| `Build.MODEL=sdk_*` | DeviceSpoof: `Pixel Tablet` | ✅ |
| `Build.FINGERPRINT` contains "sdk" | DeviceSpoof: real fingerprint | ✅ |
| `/system/bin/su` exists | Shamiko hides | ✅ |
| Magisk app installed | Magisk hide + DenyList | ✅ |
| Frida port 27042 | Different port (31337) | ✅ |
| `frida-server` process | Renamed to `hluda-server` | ✅ |
| Battery temp constant | Randomized via `cmd battery` | ✅ |
| Missing sensors | AVD config enables all | ⚠️ Partial |
| Play Integrity | Not possible on emulator | ❌ |

## Manual Verification

After setup, verify on the emulator:

### Check Device Properties
```bash
adb shell getprop ro.product.model      # Should be: Pixel Tablet
adb shell getprop ro.kernel.qemu        # Should be: 0 (or empty)
adb shell getprop ro.hardware           # Should be: tangorpro
```

### Check Magisk Modules
1. Open Magisk app (may be hidden/renamed)
2. Go to Modules tab
3. Verify `shamiko` and `device_spoof` are enabled

### Check DenyList
1. Magisk → Settings → Configure DenyList
2. Verify `com.tencent.mm` (WeChat) is checked

### Check Frida
```bash
# Start Frida
adb shell "su -c '/data/local/tmp/start-frida.sh'"

# Test connection
adb forward tcp:31337 tcp:31337
frida -H 127.0.0.1:31337 --list
```

## Troubleshooting

### Root not working after restore

```bash
# Re-run rootAVD
./bin/setup-avd restore 1
./bin/setup-avd root
```

### Device props not spoofed

```bash
# Check if module is enabled
adb shell "su -c 'ls /data/adb/modules/device_spoof/'"

# Check for disable file
adb shell "su -c 'ls /data/adb/modules/device_spoof/disable'" # Should not exist

# Reboot
adb reboot
```

### WeChat still detecting emulator

1. Check all modules are enabled in Magisk
2. Verify WeChat is in DenyList
3. Try clearing WeChat data: Settings → Apps → WeChat → Clear Data
4. Re-login to WeChat

### Snapshot restore fails

```bash
# List available snapshots
./bin/setup-avd list

# Check snapshot directory
ls ~/.android/avd/WeChat_Stealth.avd/snapshots/
```

## Usage Workflow

### Initial Setup (Once)

```bash
./bin/setup-avd all
# Download WeChat APK to wechat/downloads/
./bin/setup-avd wechat
# Login to WeChat on emulator
./bin/setup-avd snapshot    # Save production snapshot
```

### Daily Use

```bash
./bin/setup-avd restore wechat_ready   # Start from production
./bin/sync                              # Pull database
./bin/setup-avd stop                    # Or just: adb emu kill
```

### Extract Encryption Key (First Time)

```bash
# Start Frida
adb shell "su -c '/data/local/tmp/start-frida.sh'"
adb forward tcp:31337 tcp:31337

# Run extraction
frida -H 127.0.0.1:31337 -f com.tencent.mm -l lib/extract-key.js --no-pause

# Key is saved to data/config.env
```

## Security Notes

1. **Tablet mode is legitimate**: WeChat officially supports phone + tablet login
2. **Read-only usage**: We only extract the database, no marketing/bulk actions
3. **Minimize exposure**: Use snapshots, quick sessions, offline processing
4. **Key caching**: Frida only needed once to extract key, then cached

## Files Created

```
wechat/downloads/
├── rootAVD-master/      # rootAVD scripts
├── Magisk.apk           # Magisk manager
├── Shamiko.zip          # Root hiding module
├── DeviceSpoof.zip      # Device prop spoofing module
├── frida-server         # Renamed to hluda-server on device
└── *.apk                # WeChat APK (user provided)
```
