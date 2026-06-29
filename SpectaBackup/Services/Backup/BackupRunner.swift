//
//  @file        BackupRunner.swift
//  @description Actor that executes a backup pass off the main actor and serializes file I/O. It
//               resolves the job root, garbage-collects orphaned `.inprogress-*` trees from prior
//               crashes, probes the destination, opens the catalog, and drives the SnapshotEngine.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-06-29
//  @lastUpdated 2026-06-29
//
//  Notes:
//  - Being an actor, passes run serialized; the heavy copy loop is synchronous so it holds the actor
//    for the duration (effectively one pass at a time — correct for avoiding concurrent dest writes).
//  - GC runs before every pass: a `.inprogress-*` dir can only exist if a previous pass crashed, and
//    is never a valid snapshot (no COMPLETE marker, no catalog `complete` row).
//

import Foundation

enum EncryptedBackupError: Error, CustomStringConvertible {
    case passwordMissing
    case repoNotInitialized
    var description: String {
        switch self {
        case .passwordMissing: return "no repo password in Keychain for this encrypted job"
        case .repoNotInitialized: return "encrypted repo not initialized — enable encryption in Settings first"
        }
    }
}

actor BackupRunner {

    struct PassResult: Sendable {
        let snapshot: SnapshotRecord?
        let capabilities: DestinationCapabilities
    }

    /// Run one backup pass for a job.
    func run(job: BackupJob,
             quietWindow: TimeInterval = 0,
             progress: @escaping @Sendable (BackupProgress) -> Void) async throws -> PassResult {
        if job.encryptionEnabled {
            return try await runEncrypted(job: job, progress: progress)
        }
        let caps = try DestinationProbe.probe(destination: job.destination)
        if caps.strategy == .sparsebundle {
            return try await runInsideSparsebundle(job: job, quietWindow: quietWindow,
                                                   outerCaps: caps, progress: progress)
        }

        let fm = FileManager.default
        let jobRoot = Self.jobRoot(for: job)
        let snapshotsDir = jobRoot.appendingPathComponent("snapshots", isDirectory: true)
        try fm.createDirectory(at: snapshotsDir, withIntermediateDirectories: true)
        garbageCollectInProgress(in: snapshotsDir)

        let catalog = try CatalogStore(path: jobRoot.appendingPathComponent("catalog.sqlite").path)
        let engine = SnapshotEngine(catalog: catalog)
        let rec = try await engine.runPass(job: job, jobRoot: jobRoot, caps: caps,
                                           quietWindow: quietWindow, progress: progress)
        await applyRetention(job: job, snapshotsDir: snapshotsDir, catalog: catalog)
        return PassResult(snapshot: rec, capabilities: caps)
    }

    /// Encrypted path: unlock the dedup repo and run DedupEngine, recording the snapshot in the same
    /// catalog so the history/restore UI stays unified. The repo is created in Settings (where the
    /// recovery key can be shown), not here. Encrypted-repo retention (prune/GC) is a follow-up.
    private func runEncrypted(job: BackupJob,
                              progress: @escaping @Sendable (BackupProgress) -> Void) async throws -> PassResult {
        guard let password = KeychainStorage.password(for: job.id) else {
            throw EncryptedBackupError.passwordMissing
        }
        let caps = try DestinationProbe.probe(destination: job.destination)
        let jobRoot = Self.jobRoot(for: job)
        try FileManager.default.createDirectory(at: jobRoot, withIntermediateDirectories: true)
        let backend = try LocalBackend(root: jobRoot.appendingPathComponent("repo", isDirectory: true))
        guard await RepoManager.isInitialized(backend) else {
            throw EncryptedBackupError.repoNotInitialized
        }

        let (config, keys) = try await RepoManager.unlock(backend: backend, password: Data(password.utf8))
        let engine = DedupEngine(backend: backend, keys: keys, chunker: config.chunker)

        let catalog = try CatalogStore(path: jobRoot.appendingPathComponent("catalog.sqlite").path)
        let now = Date()
        let seqId = try await catalog.beginSnapshot(jobID: job.id, timestamp: now, sourceSnapshotID: nil)
        let snapshotID = "enc-\(seqId)"
        let start = Date()
        do {
            let snap = try await engine.backUp(sources: job.sources, snapshotID: snapshotID,
                                               now: now.timeIntervalSince1970)
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            try await catalog.markComplete(seqId: seqId, dirName: snapshotID, fileCount: snap.fileCount,
                                           logicalBytes: Int64(snap.totalBytes), addedBlocks: 0, durationMs: durationMs)
            let rec = SnapshotRecord(seqId: seqId, jobID: job.id, timestamp: now, dirName: snapshotID,
                                     status: .complete, fileCount: snap.fileCount,
                                     logicalBytes: Int64(snap.totalBytes), addedBlocks: 0,
                                     durationMs: durationMs, sourceSnapshotID: nil)
            return PassResult(snapshot: rec, capabilities: caps)
        } catch {
            try? await catalog.markFailed(seqId: seqId)
            throw error
        }
    }

    /// Sparsebundle path: attach an APFS image on the (clone/hardlink-less) destination and run the
    /// clone engine inside it, then always detach. History/restore for sparsebundle destinations are
    /// a follow-up (they need the same attach wrapper).
    private func runInsideSparsebundle(job: BackupJob, quietWindow: TimeInterval,
                                       outerCaps: DestinationCapabilities,
                                       progress: @escaping @Sendable (BackupProgress) -> Void) async throws -> PassResult {
        let attachment = try SparsebundleManager.attach(at: job.destination,
                                                        maxSizeBytes: job.retention.maxTotalBytes,
                                                        readOnly: false)
        defer { SparsebundleManager.detach(attachment) }

        let fm = FileManager.default
        let jobRoot = attachment.mountPoint.appendingPathComponent("SpectaBackup/\(job.id.uuidString)", isDirectory: true)
        let snapshotsDir = jobRoot.appendingPathComponent("snapshots", isDirectory: true)
        try fm.createDirectory(at: snapshotsDir, withIntermediateDirectories: true)
        garbageCollectInProgress(in: snapshotsDir)

        let innerCaps = try DestinationProbe.probe(destination: attachment.mountPoint)   // APFS → clone
        let catalog = try CatalogStore(path: jobRoot.appendingPathComponent("catalog.sqlite").path)
        let engine = SnapshotEngine(catalog: catalog)
        let rec = try await engine.runPass(job: job, jobRoot: jobRoot, caps: innerCaps,
                                           quietWindow: quietWindow, progress: progress)
        await applyRetention(job: job, snapshotsDir: snapshotsDir, catalog: catalog)
        return PassResult(snapshot: rec, capabilities: outerCaps)
    }

    /// Apply the retention policy after a pass: plan deletions and remove snapshot trees + catalog rows.
    private func applyRetention(job: BackupJob, snapshotsDir: URL, catalog: CatalogStore) async {
        guard let snaps = try? await catalog.snapshots(jobID: job.id) else { return }
        // Measure free space on the volume that actually holds the snapshots (the sparsebundle's
        // APFS volume when applicable), not the outer destination.
        let free = (try? Syscalls.volumeInfo(at: snapshotsDir.path))?.freeBytes ?? Int64.max
        let toDelete = RetentionManager.plan(policy: job.retention, snapshots: snaps, freeBytes: free, now: Date())
        guard !toDelete.isEmpty else { return }
        let byId = Dictionary(snaps.map { ($0.seqId, $0) }, uniquingKeysWith: { a, _ in a })
        for seqId in toDelete {
            guard let rec = byId[seqId], !rec.dirName.isEmpty else { continue }
            deleteSnapshotTree(snapshotsDir.appendingPathComponent(rec.dirName, isDirectory: true))
            try? await catalog.deleteSnapshot(seqId: seqId)
        }
    }

    /// Remove a snapshot directory, clearing BSD immutable flags first so deletion can't be blocked.
    private func deleteSnapshotTree(_ dir: URL) {
        try? Syscalls.clearUserFlags(dir.path)
        try? FileWalker.walk(root: dir, exclusions: BackupExclusions()) { entry in
            try? Syscalls.clearUserFlags(entry.url.path)
        }
        try? FileManager.default.removeItem(at: dir)
    }

    /// Snapshot history for a job (newest first), read from its catalog.
    func history(for job: BackupJob) async throws -> [SnapshotRecord] {
        let catalogPath = Self.jobRoot(for: job).appendingPathComponent("catalog.sqlite").path
        guard FileManager.default.fileExists(atPath: catalogPath) else { return [] }
        let catalog = try CatalogStore(path: catalogPath)
        return try await catalog.snapshots(jobID: job.id)
    }

    /// Free space at the destination, for the menu-bar gauge.
    func destinationFreeBytes(for job: BackupJob) -> Int64? {
        (try? Syscalls.volumeInfo(at: job.destination.path))?.freeBytes
    }

    /// The source-root URL inside a snapshot for a given source folder.
    func snapshotSourceRoot(job: BackupJob, snapshotDirName: String, sourceName: String) -> URL {
        Self.jobRoot(for: job)
            .appendingPathComponent("snapshots/\(snapshotDirName)/\(sourceName)", isDirectory: true)
    }

    /// Restore selected items from a snapshot into a target directory.
    func restore(job: BackupJob,
                 snapshotDirName: String,
                 sourceName: String,
                 relPaths: [String],
                 to target: URL,
                 conflict: RestoreEngine.ConflictPolicy,
                 progress: @escaping @Sendable (Int) -> Void) async throws -> RestoreEngine.Outcome {
        let sourceRoot = snapshotSourceRoot(job: job, snapshotDirName: snapshotDirName, sourceName: sourceName)
        return try RestoreEngine().restore(snapshotSourceRoot: sourceRoot,
                                           relPaths: relPaths,
                                           to: target,
                                           conflict: conflict,
                                           progress: progress)
    }

    static func jobRoot(for job: BackupJob) -> URL {
        job.destination.appendingPathComponent("SpectaBackup/\(job.id.uuidString)", isDirectory: true)
    }

    private func garbageCollectInProgress(in snapshotsDir: URL) {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: snapshotsDir.path) else { return }
        for name in entries where name.hasPrefix(".inprogress-") {
            try? FileManager.default.removeItem(at: snapshotsDir.appendingPathComponent(name))
        }
    }
}
