//
//  @file        SnapshotRecord.swift
//  @description Catalog row for one point-in-time snapshot of a job. The on-disk snapshot tree is
//               the source of truth; this record is the SQLite index entry that points at it.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-06-29
//  @lastUpdated 2026-06-29
//
//  Notes:
//  - `seqId` is the AUTHORITATIVE monotonic identity/ordering key (never reused). The timestamp-named
//    directory on disk is cosmetic — second-resolution names can collide and wall-clock can move
//    backwards (NTP/DST), so ordering must never rely on it.
//  - `logicalBytes` sums logical file sizes; `addedBlocks` counts only freshly-written on-disk blocks
//    (shared clone/hardlink extents are not re-counted) — use it for honest "added" UI figures.
//

import Foundation

enum SnapshotStatus: String, Codable, Sendable, Hashable {
    case inProgress
    case complete
    case failed
}

struct SnapshotRecord: Codable, Sendable, Identifiable, Hashable {
    /// Monotonic, authoritative ordering/identity key (never reused).
    let seqId: Int64
    let jobID: UUID
    /// Wall-clock creation time — display only, never used for ordering.
    let timestamp: Date
    /// On-disk snapshot directory name under snapshots/ (e.g. "20260629-143000-42"). Empty until complete.
    var dirName: String
    var status: SnapshotStatus
    var fileCount: Int
    var logicalBytes: Int64
    var addedBlocks: Int64
    var durationMs: Int
    /// Identifier of the APFS source snapshot used for the consistent read, if any.
    var sourceSnapshotID: String?

    var id: Int64 { seqId }
}
