//
//  @file        BackupExclusions.swift
//  @description Decides which source entries to skip: built-in system junk (Trashes, Spotlight,
//               fseventsd, …) plus user-supplied glob patterns (matched with fnmatch). The engine
//               also excludes the destination tree separately to avoid recursion.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-06-29
//  @lastUpdated 2026-06-30
//

import Darwin
import Foundation

struct BackupExclusions: Sendable {
    /// User-supplied relative glob patterns.
    let globs: [String]

    /// Directory/file names always skipped (volume metadata, caches that must never be backed up).
    static let builtInNames: Set<String> = [
        ".Trashes",
        ".Spotlight-V100",
        ".fseventsd",
        ".DocumentRevisions-V100",
        ".TemporaryItems",
        ".vol",
        ".MobileBackups",
        // Finder view metadata — rewritten just by opening a folder, so backing it up would create
        // no-op snapshots on every Finder visit. Finder regenerates it on restore.
        ".DS_Store"
    ]

    init(globs: [String] = []) {
        self.globs = globs
    }

    /// Whether an entry (by relative path and leaf name) should be excluded from the backup.
    func isExcluded(relativePath: String, name: String) -> Bool {
        if Self.builtInNames.contains(name) { return true }
        for pattern in globs {
            if fnmatch(pattern, relativePath, 0) == 0 || fnmatch(pattern, name, 0) == 0 {
                return true
            }
        }
        return false
    }
}
