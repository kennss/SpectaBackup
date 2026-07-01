# SpectArk — Roadmap / TODO

The 1.x core is complete: realtime + scheduled backups, versioned snapshots
(APFS clone / hardlink sharing), local + NAS destinations, optional encryption,
restore, retention, resume of interrupted passes, a crash-safe integrity core,
menu-bar metrics, in-app auto-update, and notarized distribution.

Below is what's intentionally left for later, roughly in priority order. Nothing here
is a known bug — these are enhancements.

## P1 — Always-on (core to the "realtime" promise)

- **Launch at login / background residency** (`SMAppService`).
  Today the app must be *running* to watch FSEvents. The menu-bar item keeps it alive
  after the window is closed, but a `Cmd-Q` or a reboot stops realtime backup until the
  user reopens the app. A login item that starts SpectArk in the background at boot is
  what makes "realtime" actually always-on. This is the most important next step.

## P2 — Deepest data integrity

- **Source APFS local snapshot for consistent reads** (torn-file prevention).
  Reading a file while it's being written can capture a half-written version. The
  fully-correct fix is to snapshot the source volume (`fs_snapshot_*`) and read from the
  frozen view. That call needs root, so it requires a privileged helper (`SMAppService`
  daemon). The engine already abstracts this behind `SourceReadSession` (currently a
  coordinated read + quiet-window), so swapping in a real snapshot session later is not a
  rewrite.

## P3 — Encrypted repo completeness

- **Partial (file-tree) restore** for encrypted jobs. Restore is currently all-or-nothing
  for encrypted repos; the plaintext path already has a file picker.
- **Prune / GC retention** for the encrypted repo (reclaim unreferenced blobs/packs).
  Retention thinning exists for plaintext snapshots but not for the dedup repo.
- **Password change** for an encrypted repo (re-wrap the key slots).

## P3 — NAS completeness

- **Sparsebundle history + restore.** The sparsebundle write path works; browsing history
  and restoring from it still need the same attach/detach wrapper. Also call
  `hdiutil compact` periodically so a deleted-from snapshot actually reclaims space.

## P4 — Robustness / nice-to-have

- **Resume on caught errors too.** Resume covers quit / crash / kill / unplug / power loss.
  A *caught* mid-pass error (e.g. a per-file permission failure) still discards the
  partial and restarts next time. Keeping the partial on any error would make it truly
  "resume from any interruption" (a partial has no COMPLETE marker, so it's safe to keep).
- **Bit-rot scrub** — periodically re-hash stored snapshots to detect silent corruption.
- **Battery / sleep gating** — option to skip or defer passes on battery; resume on wake.
- **NAS link-speed metric** — show throughput as a % of the NIC link speed for NAS jobs.
