# SpectArk

![SpectArk](docs/hero.png)

A native macOS incremental backup app (Calida Lab / Specta product family).

- **Versioned snapshots** (Time Machine style): point-in-time snapshots, unchanged
  data shared via APFS clones / hardlinks.
- **Multiple source folders**, watched live (FSEvents) or on a schedule.
- **Local disk or NAS** destinations, with strategy auto-detected per destination.
- **Optional encryption**: content-defined chunking + dedup, AES-256-GCM with
  argon2id-derived keys, and a one-time recovery key. Off by default (snapshots
  stay browsable plaintext).
- **Dashboard window + menu-bar dropdown** (live throughput, free space, last backup).
- Non-sandboxed, Developer ID distribution. macOS 14+.

## Build

The Xcode project is generated with [XcodeGen](https://github.com/yonki/XcodeGen):

```sh
brew install xcodegen      # one-time
xcodegen generate          # produces SpectaBackup.xcodeproj
open SpectaBackup.xcodeproj
```

Or from the command line:

```sh
xcodegen generate
xcodebuild -project SpectaBackup.xcodeproj -scheme SpectaBackup -configuration Release build
```

`SpectaBackup.xcodeproj` is generated and git-ignored; `project.yml` is the source of
truth. The project and scheme keep the legacy `SpectaBackup` name (and the bundle id
`ai.calidalab.spectabackup`) so existing backups, Keychain entries, and Full Disk
Access carry over across the rename; the built app is `SpectArk.app`.

## Data integrity

The backup engine is built on macOS primitives chosen for correctness:
APFS source snapshots (consistent reads), `clonefile`/`copyfile`, atomic
`rename` publish with a `COMPLETE` marker, and a SQLite catalog with
`F_FULLFSYNC` durability. See [`docs/ENCRYPTION_DESIGN.md`](docs/ENCRYPTION_DESIGN.md)
for the encrypted-repo design.
