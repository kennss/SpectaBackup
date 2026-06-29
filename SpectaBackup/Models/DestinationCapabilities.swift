//
//  @file        DestinationCapabilities.swift
//  @description Probed capabilities of a destination volume and the snapshot strategy they select.
//               Established by DestinationProbe before the first backup to a destination.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-06-29
//  @lastUpdated 2026-06-29
//
//  Notes:
//  - Strategy selection is deliberately conservative: clone (local APFS) is preferred, then
//    hardlink-tree only if hardlinks PERSIST across a remount, else the fragile sparsebundle path.
//  - `isCaseSensitive` matters for data safety: a case-insensitive destination can silently clobber
//    two source names differing only in case — the probe flags it so the engine can refuse/rename.
//

import Foundation

enum FileSystemKind: String, Codable, Sendable, Hashable {
    case apfs
    case hfsPlus
    case smb
    case other
}

enum MTimeResolution: String, Codable, Sendable, Hashable {
    case nanosecond
    case second
}

/// Snapshot materialization strategy for a destination.
enum BackupStrategy: String, Codable, Sendable, Hashable {
    /// APFS clonefile of the prior snapshot tree (local APFS). Default — Finder-browsable, ~O(1).
    case clone
    /// mkdir directories + hardlink unchanged files; fresh copy for changed (non-APFS / SMB w/ links).
    case hardlinkTree
    /// APFS sparsebundle image on a NAS supporting neither clone nor persistent hardlinks (last resort).
    case sparsebundle

    /// Choose the safest viable strategy from probed capabilities.
    static func select(from caps: DestinationCapabilities) -> BackupStrategy {
        if caps.supportsClone { return .clone }
        if caps.supportsHardlink && caps.hardlinkPersistsRemount { return .hardlinkTree }
        return .sparsebundle
    }
}

struct DestinationCapabilities: Codable, Sendable, Hashable {
    var fileSystem: FileSystemKind
    var supportsClone: Bool
    var supportsHardlink: Bool
    var hardlinkPersistsRemount: Bool
    var xattrRoundTrip: Bool
    var isCaseSensitive: Bool
    var mtimeResolution: MTimeResolution
    var freeBytes: Int64
    var probedAt: Date

    /// The strategy selected from these capabilities.
    var strategy: BackupStrategy { BackupStrategy.select(from: self) }
}
