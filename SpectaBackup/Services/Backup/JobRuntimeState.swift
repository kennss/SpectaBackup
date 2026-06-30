//
//  @file        JobRuntimeState.swift
//  @description Per-job, UI-facing runtime state (not persisted): whether a pass is running, live
//               progress, the last completed snapshot, the most recent error, and recent history.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-06-29
//  @lastUpdated 2026-06-29
//

import Foundation

struct JobRuntimeState: Sendable {
    var isRunning: Bool = false
    var progress: BackupProgress = BackupProgress()
    var lastSnapshot: SnapshotRecord?
    var lastError: String?
    var history: [SnapshotRecord] = []
    /// Smoothed write rate while a pass runs (bytes/sec); 0 when idle.
    var throughputBytesPerSec: Double = 0
    /// Free space at the destination volume (bytes); nil if unknown / unreachable.
    var destinationFreeBytes: Int64?
    /// Total capacity of the destination volume (bytes); nil if unknown.
    var destinationTotalBytes: Int64?
    /// True while a plaintext→encrypted migration runs for this job.
    var isMigrating: Bool = false
    /// Migration progress; nil when not migrating.
    var migrationProgress: MigrationProgress?
}

struct MigrationProgress: Sendable {
    var done: Int
    var total: Int
}
