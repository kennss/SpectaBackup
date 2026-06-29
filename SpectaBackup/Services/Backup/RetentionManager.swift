//
//  @file        RetentionManager.swift
//  @description Pure planner that decides which snapshots to delete for a job. First applies the
//               age/count policy (Time Machine-style thinning, keepCount, keepDays, or keepAll), then
//               relieves space pressure by dropping the OLDEST survivors while free space is below the
//               low-water mark OR total backup usage exceeds the quota (maxTotalBytes). Never drops the
//               newest snapshot. Side-effect-free and fully testable; the runner performs the actual rm.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-06-29
//  @lastUpdated 2026-06-29
//
//  Notes:
//  - Free space comes from statfs (real). Quota usage is approximated by summing snapshot addedBlocks
//    (freshly-written 512-byte blocks) — a fast, monotonic proxy for the backup's own footprint that
//    avoids walking the whole tree (shared clone/hardlink blocks aren't double-counted this way).
//

import Foundation

struct RetentionManager: Sendable {

    private static let blockSize: Int64 = 512

    /// Returns the seqIds to delete. `freeBytes` is the destination volume's current free space.
    static func plan(policy: RetentionPolicy,
                     snapshots: [SnapshotRecord],
                     freeBytes: Int64,
                     now: Date) -> [Int64] {
        let complete = snapshots
            .filter { $0.status == .complete }
            .sorted { $0.seqId < $1.seqId }                  // oldest first
        guard complete.count > 1, let newestSeq = complete.last?.seqId else { return [] }

        // 1) Age/count policy — but never the newest.
        var deleted = thinByPolicy(policy, complete: complete, now: now)
        deleted.remove(newestSeq)

        // 2) Space pressure & quota — drop oldest survivors until satisfied.
        var survivors = complete.filter { !deleted.contains($0.seqId) }   // already oldest-first
        var liveFree = freeBytes
        var liveUsage = survivors.reduce(Int64(0)) { $0 + $1.addedBlocks * blockSize }

        while survivors.count > 1 {
            let lowFree = policy.minimumFreeBytes > 0 && liveFree < policy.minimumFreeBytes
            let overQuota = policy.maxTotalBytes > 0 && liveUsage > policy.maxTotalBytes
            guard lowFree || overQuota else { break }
            let oldest = survivors.removeFirst()
            let freed = oldest.addedBlocks * blockSize
            liveFree = (liveFree > Int64.max - freed) ? Int64.max : liveFree + freed   // saturating
            liveUsage -= freed
            deleted.insert(oldest.seqId)
        }

        return Array(deleted)
    }

    // MARK: - Policy thinning

    private static func thinByPolicy(_ policy: RetentionPolicy,
                                     complete: [SnapshotRecord],
                                     now: Date) -> Set<Int64> {
        switch policy.mode {
        case .keepAll:
            return []
        case .keepCount(let n):
            guard n >= 1, complete.count > n else { return [] }
            return Set(complete.prefix(complete.count - n).map(\.seqId))   // drop oldest beyond n
        case .keepDays(let d):
            let cutoff = now.addingTimeInterval(-Double(d) * 86_400)
            return Set(complete.filter { $0.timestamp < cutoff }.map(\.seqId))
        case .automatic:
            return automaticThinning(complete, now: now)
        }
    }

    /// Time Machine style: keep everything < 24h, newest-per-day for ~30d, newest-per-week beyond.
    private static func automaticThinning(_ complete: [SnapshotRecord], now: Date) -> Set<Int64> {
        var keep = Set<Int64>()
        var dayBuckets = Set<Int>()
        var weekBuckets = Set<Int>()
        // Newest-first so the first snapshot seen in each bucket (the newest) is the one we keep.
        for snap in complete.sorted(by: { $0.seqId > $1.seqId }) {
            let age = now.timeIntervalSince(snap.timestamp)
            if age < 86_400 {
                keep.insert(snap.seqId)
            } else if age < 30 * 86_400 {
                let day = Int(snap.timestamp.timeIntervalSince1970 / 86_400)
                if dayBuckets.insert(day).inserted { keep.insert(snap.seqId) }
            } else {
                let week = Int(snap.timestamp.timeIntervalSince1970 / (7 * 86_400))
                if weekBuckets.insert(week).inserted { keep.insert(snap.seqId) }
            }
        }
        return Set(complete.map(\.seqId)).subtracting(keep)
    }
}
