# WeChat Docker/Redroid Setup

## Overview

Redroid runs Android in a container, but requires Linux kernel modules (binder, ashmem) that aren't available on macOS directly.

```
Mac → Lima VM (Ubuntu + binder) → Docker → Redroid → WeChat
```

## Quick Start (macOS)

```bash
# Install Lima
brew install lima

# Full setup (first time)
./lima-setup.sh setup

# Install WeChat
./lima-setup.sh install

# Open WeChat for login
./lima-setup.sh login
```

## Commands

| Command | Description |
|---------|-------------|
| `./lima-setup.sh setup` | Create VM, load modules, start Redroid |
| `./lima-setup.sh start` | Start VM and Redroid (after initial setup) |
| `./lima-setup.sh stop` | Stop Redroid and VM |
| `./lima-setup.sh status` | Show status of all components |
| `./lima-setup.sh shell` | SSH into the Lima VM |
| `./lima-setup.sh install` | Install WeChat APK |
| `./lima-setup.sh login` | Open WeChat for QR login |
| `./lima-setup.sh delete` | Delete the Lima VM completely |

## How It Works

### The Problem

Redroid needs Linux kernel features that macOS doesn't have:

| Feature | Purpose | macOS | Linux |
|---------|---------|-------|-------|
| binder | Android IPC | ❌ | ✅ |
| ashmem | Shared memory | ❌ | ✅ |

Docker Desktop's hidden Linux VM doesn't include these either.

### The Solution

Lima runs a full Linux VM where we can add binder support:

1. **Lima VM**: Ubuntu with customizable kernel
2. **redroid-modules**: Adds binder/ashmem as loadable modules
3. **Docker**: Runs inside the VM
4. **Redroid**: Android container with binder access

### Architecture

```
┌─────────────────────────────┐
│  WeChat (Android app)       │
├─────────────────────────────┤
│  Redroid (Android container)│
├─────────────────────────────┤
│  Docker                     │
├─────────────────────────────┤
│  Ubuntu + binder modules    │  ← Lima VM
├─────────────────────────────┤
│  macOS                      │
└─────────────────────────────┘
```

## Requirements

- macOS with Apple Silicon (M1/M2/M3/M4)
- Lima: `brew install lima`
- ADB: `brew install android-platform-tools`
- scrcpy (for screen): `brew install scrcpy`
- WeChat APK: download from https://www.wandoujia.com/apps/596157

## Files

```
docker/
├── lima-setup.sh    # macOS setup via Lima
├── setup.sh         # Linux-only setup (direct Redroid)
├── wechat.apk       # WeChat APK (download yourself)
└── README.md
```

## Troubleshooting

### Module loading fails

If `modprobe binder_linux` fails, the kernel may not support it. Options:

1. Try a different Ubuntu version in lima config
2. Compile custom kernel with `CONFIG_ANDROID_BINDERFS=y`
3. Use Android AVD instead (simpler for Mac)

### Redroid container crashes

Check logs:
```bash
./lima-setup.sh shell
docker logs redroid
```

### ADB can't connect

Make sure port 5555 is forwarded:
```bash
./lima-setup.sh status
```

## Alternative: Android AVD

If Lima + Redroid is too complex, Android AVD works directly on Mac:

```bash
# Install Android Studio or command-line tools
# Create AVD with Android 11+
# Run emulator
# Use the existing wechat tool with AVD
```

AVD is heavier but simpler to set up on Mac.
