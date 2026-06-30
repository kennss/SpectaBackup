//
//  @file        DestinationUsage.swift
//  @description Free/total space of one backup destination VOLUME (SSD, external disk, or mounted
//               NAS share), aggregated across all jobs that back up to the same disk. Shown in the
//               sidebar footer and the menu bar so the user can see every backup target's capacity.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-06-30
//  @lastUpdated 2026-06-30
//

import Foundation

struct DestinationUsage: Identifiable, Sendable, Hashable {
    /// Volume mount path (also the stable identity — jobs on the same disk collapse into one row).
    let id: String
    let name: String
    let freeBytes: Int64
    let totalBytes: Int64
    var jobCount: Int

    var usedFraction: Double {
        totalBytes > 0 ? Double(totalBytes - freeBytes) / Double(totalBytes) : 0
    }
}
