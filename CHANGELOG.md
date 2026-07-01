# Changelog

All notable changes to SpectArk are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/), and the project uses
[Semantic Versioning](https://semver.org/).

## [1.1.0] — 2026-07-01

### Added
- **Resume interrupted backups.** If a backup stops midway (quit, crash, drive
  unplugged), the next run continues from where it left off instead of restarting
  from scratch.
- **In-app auto-update** (Sparkle). SpectArk checks a signed appcast for newer
  notarized builds and can update itself — *Check for Updates…* in the app menu and
  the menu-bar dropdown.
- **Back Up Now** button in the job detail view.

### Fixed
- NAS / network (SMB) volumes now show their real free space in the sidebar and
  menu bar instead of "Zero KB free".
- The window no longer opens larger than the screen on launch (an oversized restored
  frame is shrunk to fit and re-centered).

## [1.0.0] — 2026-06-30

First public release. Rebranded from SpectaBackup to **SpectArk** (display name only;
the bundle id and existing backups carry over).

### Added
- **Realtime or scheduled** backups per job — watch a folder live (FSEvents) and
  snapshot on change, or run on an interval.
- **Versioned snapshots** (Time Machine style), unchanged data shared via APFS
  clones / hardlinks.
- **Any source → any destination** — local disk or NAS, no dedicated backup drive
  required.
- **Optional encryption** — content-defined chunking + dedup, AES-256-GCM with
  argon2id-derived keys, and a one-time recovery key. Off by default (snapshots stay
  browsable plaintext).
- Dashboard window + menu-bar dropdown with live throughput and free space.
- Developer ID signed and notarized; universal (Apple Silicon + Intel), macOS 14+.

[1.1.0]: https://github.com/kennss/SpectArk/releases/tag/v1.1.0
[1.0.0]: https://github.com/kennss/SpectArk/releases/tag/v1.0.0
