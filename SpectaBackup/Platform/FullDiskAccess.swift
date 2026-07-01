//
//  @file        FullDiskAccess.swift
//  @description Detects whether the app has Full Disk Access (required, even when non-sandboxed, to
//               read protected source folders like Desktop/Documents) and opens the relevant System
//               Settings pane. Without FDA the app would silently produce incomplete backups.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-06-29
//  @lastUpdated 2026-07-01
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

    /// Quit and relaunch the app. Granting Full Disk Access to an already-running process only takes
    /// effect after a restart, so the onboarding offers this once the user has granted access.
    @MainActor
    static func relaunchApp() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; open \"\(path)\""]
        try? task.run()
        NSApp.terminate(nil)
    }
}
