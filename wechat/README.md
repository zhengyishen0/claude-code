# WeChat Tools

Run WeChat in Android emulator with tablet mode support for message search and database access.

## Quick Start

### Option 1: AVD (Recommended for Mac)
```bash
./bin/avd start          # Start emulator with snapshot
./bin/avd stop           # Save snapshot and stop
```

### Option 2: Lima + Redroid (Docker-based)
```bash
./bin/lima start         # Start Lima VM
./bin/redroid start      # Start Redroid tablet container
./bin/redroid scrcpy     # Open interactive window
```

## Commands

| Command | Description |
|---------|-------------|
| `./bin/avd start` | Start AVD from snapshot (~5s) |
| `./bin/avd stop` | Save snapshot and stop |
| `./bin/lima start` | Start Lima VM |
| `./bin/redroid start` | Start Redroid tablet |
| `./bin/redroid scrcpy` | Open scrcpy for interaction |
| `./bin/view start` | Web viewer at localhost:8080 |
| `./bin/sync` | Pull database from device |

## Architecture

```
Option 1 (AVD):
Mac → AVD (qemu) → Android 35 → WeChat
      └── Snapshots: ~5s resume

Option 2 (Redroid):
Mac → Lima VM → Docker → Redroid → WeChat
      └── No snapshots, but lighter weight
```

## Comparison

| Feature | AVD | Redroid |
|---------|-----|---------|
| Setup | Easy | Medium |
| Snapshot | Yes (5s resume) | No |
| RAM | ~3GB | ~6GB (VM+container) |
| Heat/CPU | Lower | Higher |
| Tablet mode | Native | Spoofed (works) |

## Directory Structure

```
wechat/
├── bin/           # All commands
│   ├── avd        # AVD management
│   ├── lima       # Lima VM management
│   ├── redroid    # Redroid container (tablet mode)
│   ├── view       # Web viewer
│   ├── sync       # Database sync
│   ├── init       # Setup & decrypt
│   ├── search     # Search messages
│   └── wechat     # Main entry point
├── config/        # Configuration
│   ├── lima.yaml  # Lima VM config
│   └── redroid.env # Redroid settings
├── lib/           # Supporting modules
├── docs/          # Documentation
├── downloads/     # APKs (gitignored)
└── data/          # Synced databases (gitignored)
```

## Requirements

- macOS with Apple Silicon
- For AVD: `brew install android-platform-tools`
- For Redroid: `brew install lima scrcpy`
- WeChat APK (place in downloads/)

## See Also

- [Architecture Details](docs/architecture.md)
- [Troubleshooting](docs/troubleshooting.md)
