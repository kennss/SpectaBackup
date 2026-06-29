//
//  @file        SnapshotEngine.swift
//  @description The core backup engine. Implements the CLONE strategy (local APFS): clone the prior
//               COMPLETE snapshot tree with clonefile (CoW), then apply the source diff — fresh-copy
//               changed/new files, hardlink intra-source duplicates, and unlink deletions. Publishes
//               atomically via .inprogress → fsync → rename → COMPLETE marker → catalog commit.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-06-29
//  @lastUpdated 2026-06-29
//
//  Safety invariants (from the engine design review):
//  - Clone files are independent inodes (CoW), so overwriting a changed file in the new snapshot can
//    never mutate a previous snapshot. We still always unlink-then-copy (never write in place) for
//    clean metadata. The hardlink strategy (separate, M2) has the opposite, dangerous semantics.
//  - A snapshot is valid only when renamed to its final path AND carrying the COMPLETE marker AND
//    recorded `complete` in the catalog. Crashes leave a `.inprogress-*` dir that is GC'd on launch.
//  - On a destination-gone error the pass aborts and discards the in-progress tree (never writes into
//    an unmounted mountpoint).
//  - Empty incremental snapshots are skipped (no no-op snapshots polluting retention).
//

import Darwin
import Foundation

struct SnapshotEngine: Sendable {

    enum EngineError: Error, CustomStringConvertible {
        case unsupportedStrategy(BackupStrategy)
        case destinationGone(String)

        var description: String {
            switch self {
            case let .unsupportedStrategy(s): return "snapshot strategy not implemented in M1: \(s.rawValue)"
            case let .destinationGone(p): return "destination volume disappeared mid-pass: \(p)"
            }
        }
    }

    static let completeMarker = ".spectabackup-complete"

    let catalog: CatalogStore

    private static let dirNameFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    // MARK: - Public entry

    /// Run one backup pass for `job` into `jobRoot`. Returns the new snapshot record, or nil if an
    /// incremental pass found nothing changed (empty snapshot skipped).
    func runPass(job: BackupJob,
                 jobRoot: URL,
                 caps: DestinationCapabilities,
                 quietWindow: TimeInterval = 0,
                 progress: @escaping @Sendable (BackupProgress) -> Void) async throws -> SnapshotRecord? {
        // clone (local APFS) and hardlinkTree (NAS w/ persistent hardlinks) are implemented;
        // sparsebundle is a later milestone.
        guard caps.strategy != .sparsebundle else { throw EngineError.unsupportedStrategy(caps.strategy) }

        let fm = FileManager.default
        let snapshotsDir = jobRoot.appendingPathComponent("snapshots", isDirectory: true)
        try fm.createDirectory(at: snapshotsDir, withIntermediateDirectories: true)

        let base = try await catalog.latestComplete(jobID: job.id)
        let baseDir = base.flatMap { rec -> URL? in
            rec.dirName.isEmpty ? nil : snapshotsDir.appendingPathComponent(rec.dirName, isDirectory: true)
        }

        let startTime = Date()
        let seqId = try await catalog.beginSnapshot(jobID: job.id, timestamp: startTime, sourceSnapshotID: nil)
        let inProgressDir = snapshotsDir.appendingPathComponent(".inprogress-\(seqId)", isDirectory: true)

        do {
            // 1) Materialize the base tree (CoW clone) or start fresh for the first snapshot.
            if let baseDir, fm.fileExists(atPath: baseDir.path) {
                // Materialize the base tree per strategy: APFS CoW clone, or a hardlink tree for
                // destinations with persistent hardlinks but no clonefile (e.g. some NAS shares).
                if caps.strategy == .hardlinkTree {
                    try materializeHardlinkTree(base: baseDir, into: inProgressDir)
                } else {
                    try Syscalls.cloneItem(at: baseDir.path, to: inProgressDir.path)
                }
                // The base carries the previous COMPLETE marker — remove it; we re-add it on success.
                try? fm.removeItem(at: inProgressDir.appendingPathComponent(Self.completeMarker))
            } else {
                try fm.createDirectory(at: inProgressDir, withIntermediateDirectories: true)
            }

            var stats = PassStats()
            for source in job.sources {
                try syncSource(source: source,
                               into: inProgressDir,
                               caps: caps,
                               exclusions: BackupExclusions(globs: job.excludeGlobs),
                               quietWindow: quietWindow,
                               stats: &stats,
                               progress: progress)
            }

            // 2) Skip empty incremental snapshots (nothing changed since base).
            if base != nil && stats.changedCount == 0 {
                try? fm.removeItem(at: inProgressDir)
                try await catalog.deleteSnapshot(seqId: seqId)
                return nil
            }

            // 3) Atomic publish: COMPLETE marker → fsync → rename → fsync parent → catalog commit.
            let markerURL = inProgressDir.appendingPathComponent(Self.completeMarker)
            try Data().write(to: markerURL)
            try Syscalls.syncDirectory(inProgressDir.path)

            let dirName = "\(Self.dirNameFormatter.string(from: startTime))-\(seqId)"
            let finalDir = snapshotsDir.appendingPathComponent(dirName, isDirectory: true)
            try Syscalls.atomicRename(inProgressDir.path, to: finalDir.path)
            try Syscalls.syncDirectory(snapshotsDir.path)

            let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
            try await catalog.markComplete(seqId: seqId,
                                           dirName: dirName,
                                           fileCount: stats.fileCount,
                                           logicalBytes: stats.logicalBytes,
                                           addedBlocks: stats.addedBlocks,
                                           durationMs: durationMs)
            updateLatestSymlink(snapshotsDir: snapshotsDir, dirName: dirName, seqId: seqId)

            return SnapshotRecord(seqId: seqId,
                                  jobID: job.id,
                                  timestamp: startTime,
                                  dirName: dirName,
                                  status: .complete,
                                  fileCount: stats.fileCount,
                                  logicalBytes: stats.logicalBytes,
                                  addedBlocks: stats.addedBlocks,
                                  durationMs: durationMs,
                                  sourceSnapshotID: nil)
        } catch {
            // Discard the half-written tree and mark the row failed; never leave a partial snapshot.
            try? FileManager.default.removeItem(at: inProgressDir)
            try? await catalog.markFailed(seqId: seqId)
            if let infra = error as? InfraError, infra.isVolumeGone {
                throw EngineError.destinationGone(infra.path ?? jobRoot.path)
            }
            throw error
        }
    }

    // MARK: - Per-source sync

    private func syncSource(source: URL,
                            into inProgressDir: URL,
                            caps: DestinationCapabilities,
                            exclusions: BackupExclusions,
                            quietWindow: TimeInterval,
                            stats: inout PassStats,
                            progress: @escaping @Sendable (BackupProgress) -> Void) throws {
        let fm = FileManager.default
        let session = SourceSnapshotProvider.beginSession(for: source, quietWindow: quietWindow)
        defer { session.cleanup() }

        let sourceRoot = session.rootURL
        // Each source lands under its own subdirectory (named after the source folder).
        let destRoot = inProgressDir.appendingPathComponent(source.lastPathComponent, isDirectory: true)
        try fm.createDirectory(at: destRoot, withIntermediateDirectories: true)

        var seen = Set<String>()
        var inodeToRelPath = [ino_t: String]()   // first copied path per inode (intra-source hardlinks)
        var prog = BackupProgress()

        try FileWalker.walk(root: sourceRoot, exclusions: exclusions) { entry in
            seen.insert(entry.relativePath)
            let destPath = destRoot.appendingPathComponent(entry.relativePath).path
            stats.fileCount += 1

            if entry.isDirectory {
                if !fm.fileExists(atPath: destPath) {
                    try fm.createDirectory(atPath: destPath, withIntermediateDirectories: true)
                }
                return
            }

            stats.logicalBytes += entry.size

            // Intra-source hardlink: link to the already-copied destination file (rsync -H behavior).
            if entry.isHardlinked, let firstRel = inodeToRelPath[entry.ino] {
                let target = destRoot.appendingPathComponent(firstRel).path
                removeIfPresent(destPath)
                try Syscalls.hardlink(from: target, to: destPath)
                stats.changedCount += 1
                return
            }

            // Defer files that may be mid-write (within the quiet window). Keeps the base version.
            if session.shouldDefer(modificationDate: entry.mtime) { return }

            // Copy only if new or changed vs the cloned base file.
            if isChanged(source: entry, destPath: destPath, caps: caps) {
                removeIfPresent(destPath)
                try Syscalls.copyItem(at: entry.url.path, to: destPath)
                stats.changedCount += 1
                stats.addedBlocks += entry.blocks
                stats.bytesCopied += entry.size
                prog.filesProcessed = stats.fileCount
                prog.bytesCopied = stats.bytesCopied
                prog.currentPath = entry.relativePath
                progress(prog)
            }

            if entry.isHardlinked { inodeToRelPath[entry.ino] = entry.relativePath }
        }

        // Deletions: anything in the cloned tree no longer present in the source is removed.
        try removeOrphans(in: destRoot, keeping: seen, stats: &stats)
    }

    // MARK: - Hardlink-tree materialization (NAS strategy)

    /// Reproduce the base snapshot tree using hardlinks (for destinations with persistent hardlinks
    /// but no clonefile). Directories are recreated (APFS has no directory hardlinks); regular files
    /// are hardlinked to share data with the base; symlinks are recreated. Changed files are later
    /// replaced by syncSource via unlink-then-copy — never written in place — so the base snapshot
    /// (which shares those inodes) is never mutated.
    private func materializeHardlinkTree(base: URL, into: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: into, withIntermediateDirectories: true)
        try FileWalker.walk(root: base, exclusions: BackupExclusions()) { entry in
            let dst = into.appendingPathComponent(entry.relativePath).path
            if entry.isDirectory {
                try fm.createDirectory(atPath: dst, withIntermediateDirectories: true)
            } else if entry.isSymlink {
                try Syscalls.copyItem(at: entry.url.path, to: dst)   // recreate the link itself
            } else {
                try Syscalls.hardlink(from: entry.url.path, to: dst)
            }
        }
    }

    // MARK: - Helpers

    private func isChanged(source: FileEntry, destPath: String, caps: DestinationCapabilities) -> Bool {
        var ds = Darwin.stat()
        guard lstat(destPath, &ds) == 0 else { return true }            // absent → new file
        if Int64(ds.st_size) != source.size { return true }
        let destMtime = Double(ds.st_mtimespec.tv_sec) + Double(ds.st_mtimespec.tv_nsec) / 1_000_000_000
        let tolerance = caps.mtimeResolution == .second ? 2.0 : 0.001
        return abs(source.mtime.timeIntervalSince1970 - destMtime) > tolerance
    }

    private func removeOrphans(in destRoot: URL, keeping seen: Set<String>, stats: inout PassStats) throws {
        var orphans: [String] = []
        try FileWalker.walk(root: destRoot, exclusions: BackupExclusions()) { entry in
            if !seen.contains(entry.relativePath) { orphans.append(entry.relativePath) }
        }
        // Remove deepest paths first so parent directory removal doesn't race child entries.
        for rel in orphans.sorted(by: { $0.count > $1.count }) {
            removeIfPresent(destRoot.appendingPathComponent(rel).path)
            stats.changedCount += 1
        }
    }

    /// Remove a path if it exists, first clearing BSD flags (e.g. uchg) that would block deletion.
    private func removeIfPresent(_ path: String) {
        guard FileManager.default.fileExists(atPath: path) else { return }
        try? Syscalls.clearUserFlags(path)
        try? FileManager.default.removeItem(atPath: path)
    }

    private func updateLatestSymlink(snapshotsDir: URL, dirName: String, seqId: Int64) {
        let fm = FileManager.default
        let tmp = snapshotsDir.appendingPathComponent(".latest-\(seqId)")
        let latest = snapshotsDir.appendingPathComponent("latest")
        try? fm.removeItem(at: tmp)
        try? fm.createSymbolicLink(atPath: tmp.path, withDestinationPath: dirName)
        try? Syscalls.atomicRename(tmp.path, to: latest.path)
    }
}

/// Mutable accumulator for one pass.
private struct PassStats {
    var fileCount = 0
    var logicalBytes: Int64 = 0
    var addedBlocks: Int64 = 0
    var bytesCopied: Int64 = 0
    /// Copies + hardlink relinks + deletions. Zero on an incremental pass ⇒ skip the snapshot.
    var changedCount = 0
}
