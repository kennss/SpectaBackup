# SpectaBackup

A native macOS incremental backup app (Calida Lab / Specta product family).

- **Versioned snapshots** (Time Machine style): point-in-time snapshots, unchanged
  data shared via APFS clones / hardlinks.
- **Multiple source folders**, watched live (FSEvents) or on a schedule.
- **Local disk or NAS** destinations, with strategy auto-detected per destination.
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
xcodebuild -project SpectaBackup.xcodeproj -scheme SpectaBackup -configuration Debug build
```

`SpectaBackup.xcodeproj` is generated and git-ignored; `project.yml` is the source of truth.

## Data integrity

The backup engine is built on macOS primitives chosen for correctness:
APFS source snapshots (consistent reads), `clonefile`/`copyfile`, atomic
`rename` publish with a `COMPLETE` marker, and a SQLite catalog with
`F_FULLFSYNC` durability. See `/Users/kennt/.claude/plans/clever-dancing-dolphin.md`
for the full design rationale.
