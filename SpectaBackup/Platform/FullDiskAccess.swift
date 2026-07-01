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
//  - Detection opens the user TCC.db for reading (only possible with Full Disk Access). We open+read
//    rather than access()/isReadableFile because the latter doesn't reliably reflect TCC. The
//    onboarding card is also dismissible, so a wrong negative never blocks the user; real per-source
//    read failures are surfaced as job errors regardless.
//

import AppKit
import Foundation

enum FullDiskAccess {
    static var isGranted: Bool {
        let path = ("~/Library/Application Support/com.apple.TCC/TCC.db" as NSString).expandingTildeInPath
        // The user TCC.db is only readable with Full Disk Access. Probe it with a real open + read —
        // that actually goes through TCC. `access()` / `isReadableFile` does NOT reliably reflect TCC
        // (it returned false even with FDA granted on recent macOS, wrongly showing the onboarding).
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else {
            // Open failed: either denied (no FDA) or the file is missing. If it's missing we can't
            // tell, so don't hard-gate — real per-source read failures still surface as job errors.
            return !FileManager.default.fileExists(atPath: path)
        }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 1)) != nil
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
