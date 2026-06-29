//
//  @file        FullDiskAccess.swift
//  @description Detects whether the app has Full Disk Access (required, even when non-sandboxed, to
//               read protected source folders like Desktop/Documents) and opens the relevant System
//               Settings pane. Without FDA the app would silently produce incomplete backups.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-06-29
//  @lastUpdated 2026-06-29
//
//  Notes:
//  - Heuristic: TCC.db is only readable with Full Disk Access granted. Cheap and reliable enough to
//    gate the onboarding banner; per-source read failures are still surfaced as job errors.
//

import AppKit
import Foundation

enum FullDiskAccess {
    static var isGranted: Bool {
        let path = ("~/Library/Application Support/com.apple.TCC/TCC.db" as NSString).expandingTildeInPath
        return FileManager.default.isReadableFile(atPath: path)
    }

    @MainActor
    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
