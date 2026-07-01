//
//  @file        DestinationStatus.swift
//  @description Lightweight, synchronous checks on a backup destination's availability, used by the UI
//               to tell "the NAS / disk is disconnected" apart from other failures (e.g. Full Disk
//               Access). A disconnected destination shows a reconnect card instead of the FDA message.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-07-01
//  @lastUpdated 2026-07-01
//

import Foundation

enum DestinationStatus {
    /// The destination is currently mounted and writable (i.e. a backup could be written now).
    static func isReachable(_ url: URL) -> Bool {
        FileManager.default.isWritableFile(atPath: url.path)
    }

    /// True when the destination is (or was) a network share — SMB / NFS / AFP / WebDAV. When the share
    /// is unmounted we can't statfs it, so we fall back to "any non-boot `/Volumes` mount", which lets
    /// the reconnect card say "drive or NAS share" without over-claiming.
    static func isNetworkVolume(_ url: URL) -> Bool {
        if let info = try? Syscalls.volumeInfo(at: url.path) {
            let t = info.fsTypeName.lowercased()
            return t.contains("smb") || t.contains("nfs") || t.contains("afp") || t.contains("webdav")
        }
        return url.path.hasPrefix("/Volumes/")
    }
}
