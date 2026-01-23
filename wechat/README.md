# WeChat Tools

Run WeChat in Android emulator with tablet mode support for message search and database access.

## Quick Start

```bash
./bin/avd start          # Start emulator with snapshot
./bin/avd stop           # Save snapshot and stop
```

## Commands

| Command | Description |
|---------|-------------|
| `./bin/avd start` | Start AVD from snapshot |
| `./bin/avd stop` | Save snapshot and stop |
| `./bin/avd snapshot` | Save current state |
| `./bin/avd status` | Show AVD status |
| `./bin/view start` | Web viewer at localhost:8080 |
| `./bin/sync` | Pull database from device |

## Architecture

```
Mac → AVD (qemu) → Android 35 → WeChat
      └── Snapshots for fast resume
```

## Directory Structure

```
wechat/
├── bin/           # All commands
│   ├── avd        # AVD management
│   ├── view       # Web viewer
│   ├── sync       # Database sync
│   ├── init       # Setup & decrypt
│   ├── search     # Search messages
│   └── wechat     # Main entry point
├── archive/       # Archived implementations
│   └── redroid/   # Lima + Redroid (Docker-based alternative)
├── config/        # Configuration
├── lib/           # Supporting modules
├── docs/          # Documentation
├── downloads/     # APKs (gitignored)
└── data/          # Synced databases (gitignored)
```

## Requirements

- macOS with Apple Silicon
- `brew install android-platform-tools`
- WeChat APK (place in downloads/)

## See Also

- [Architecture Details](docs/architecture.md)
- [Troubleshooting](docs/troubleshooting.md)
