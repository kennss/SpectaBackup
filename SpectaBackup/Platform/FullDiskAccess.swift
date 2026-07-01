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
//  - We detect FDA by trying to ENUMERATE a TCC-protected folder (opendir), NOT by reading TCC.db.
//    On macOS 15/26 the ~/Library/Application Support/com.apple.TCC directory is special-cased and is
//    NOT unlocked by a normal FDA grant (only TCC-privileged processes read it), so probing TCC.db gave
//    false negatives even with FDA on. Ordinary protected folders (Safari/Cookies/Mail) ARE unlocked by
//    FDA: opendir() returns EPERM without FDA and succeeds with it. We distinguish EPERM (real denial)
//    from ENOENT (folder absent) so a missing folder never counts as "denied". The onboarding card is
//    also dismissible, and real per-source read failures surface as job errors regardless.
//

import AppKit
import Foundation

enum FullDiskAccess {

    /// TCC-protected locations that a Full Disk Access grant unlocks, tried in order. These are ordinary
    /// protected user folders (present on essentially every Mac) — NOT ~/Library/Application Support/
    /// com.apple.TCC, which macOS 15/26 special-cases so that even an FDA-granted app cannot read it.
    private static let protectedProbePaths: [String] = [
        "~/Library/Safari",
        "~/Library/Cookies",
        "~/Library/Containers/com.apple.Safari",
        "~/Library/Mail",
    ]

    static var isGranted: Bool {
        var sawDenial = false
        for path in protectedProbePaths {
            switch probe(expandTilde(path)) {
            case .granted:
                return true          // Definitive: we listed a protected folder → FDA is effective.
            case .denied:
                sawDenial = true     // Definitive TCC denial for this path; keep checking others.
            case .inconclusive:
                continue             // Folder absent on this Mac; try the next candidate.
            }
        }
        // No probe succeeded. If at least one gave a hard TCC denial (EPERM/EACCES), FDA is genuinely off
        // → return false and show the card. If every candidate was merely absent (nothing to read, and
        // nothing denied), stay conservative and assume granted: the card is dismissible and real
        // per-source read failures already surface as job errors, so we must not nag on a false negative.
        return !sawDenial
    }

    private enum ProbeResult { case granted, denied, inconclusive }

    /// Try to open a directory for enumeration. Succeeding means this process can list a TCC-protected
    /// folder, i.e. Full Disk Access is active. We use opendir()/errno directly (rather than FileManager)
    /// so we can cleanly separate a TCC denial (EPERM/EACCES) from the folder simply not existing
    /// (ENOENT/ENOTDIR). Verified on macOS 26 (Darwin 25.5): without FDA every protected folder returns
    /// EPERM from opendir even though it exists.
    private static func probe(_ path: String) -> ProbeResult {
        errno = 0
        if let dir = opendir(path) {
            closedir(dir)
            return .granted
        }
        switch errno {
        case EPERM, EACCES:
            return .denied
        default:            // ENOENT, ENOTDIR, etc. — the path isn't present to test.
            return .inconclusive
        }
    }

    /// Expand a leading "~" against the real home directory via getpwuid, robust regardless of HOME.
    private static func expandTilde(_ path: String) -> String {
        guard path.hasPrefix("~") else { return path }
        guard let pw = getpwuid(getuid()) else { return (path as NSString).expandingTildeInPath }
        return String(cString: pw.pointee.pw_dir) + path.dropFirst()
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
