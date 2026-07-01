//
//  @file        BackupErrorMessage.swift
//  @description Turns raw NSError / POSIX failures into short, human-readable messages for the UI,
//               so the user sees "The backup disk was disconnected." instead of a giant NSError dump.
//               Maps the common backup failure cases: disk ejected/unreachable, out of space, read-only,
//               permission/Full Disk Access, plus our own typed errors.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-06-30
//  @lastUpdated 2026-07-01
//

import Foundation

enum BackupErrorMessage {

    /// A concise, user-facing sentence for any backup/restore/migration error.
    static func describe(_ error: Error) -> String {
        // Our own typed errors already carry friendly descriptions.
        if let e = error as? EncryptedBackupError { return e.description }
        if let e = error as? RepoCryptoError { return e.description }
        if let e = error as? RepoManagerError { return e.description }
        if let e = error as? BlobStoreError { return e.description }

        let ns = error as NSError

        // Prefer the underlying POSIX cause (most disk failures surface here).
        if let posix = posixCode(ns) {
            switch posix {
            case ENOSPC:
                return "The backup disk is full."
            case ENOTCONN, ENXIO, EIO, ENODEV:
                return "The backup disk was disconnected. Reconnect it and try the backup again."
            case ENOENT, ENOTDIR:
                return "The backup disk or a file is no longer available — the disk may have been ejected mid-backup."
            case EACCES, EPERM:
                return "Permission denied. Grant SpectArk Full Disk Access in System Settings, then quit and reopen the app."
            case EROFS:
                return "The backup disk is read-only."
            default: break
            }
        }

        switch ns.code {
        case NSFileWriteOutOfSpaceError:
            return "The backup disk is full."
        case NSFileWriteVolumeReadOnlyError:
            return "The backup disk is read-only."
        case NSFileReadNoSuchFileError, NSFileNoSuchFileError:
            return "The backup disk or a file is no longer available — was it ejected?"
        case NSFileReadNoPermissionError, NSFileWriteNoPermissionError:
            return "Permission denied. Grant SpectaBackup Full Disk Access in System Settings."
        default: break
        }

        return "The backup couldn’t finish — the disk may have been disconnected or a file became unavailable."
    }

    /// Walk the NSUnderlyingError chain to find a POSIX errno, if any.
    private static func posixCode(_ error: NSError) -> Int32? {
        var current: NSError? = error
        while let e = current {
            if e.domain == NSPOSIXErrorDomain { return Int32(e.code) }
            current = e.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return nil
    }
}
