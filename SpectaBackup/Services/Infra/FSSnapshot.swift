//
//  @file        FSSnapshot.swift
//  @description Wrapper over the APFS fs_snapshot SPI (exposed via Infra-Bridging.h). Used to take a
//               consistent, frozen read view of a SOURCE volume for the duration of a backup pass so
//               files being saved are never captured half-written (the torn-file problem).
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-06-29
//  @lastUpdated 2026-06-29
//
//  Notes:
//  - `create`/`delete` operate on an open fd of the VOLUME ROOT and are available to a normal user.
//  - `mount` typically requires elevated privileges; SourceSnapshotProvider decides whether mounting
//    is viable and falls back to coordinated reads when it is not. Mounting is gated there, not here.
//  - All calls return 0 on success, -1 on failure with errno set.
//

import Darwin
import Foundation

enum FSSnapshot {
    /// Create a named snapshot of the volume whose root is `volumeRootFD`.
    static func create(name: String, volumeRootFD fd: Int32) throws {
        if fs_snapshot_create(fd, name, 0) != 0 {
            throw InfraError(operation: "fs_snapshot_create", path: name, code: errno)
        }
    }

    /// Delete a named snapshot of the volume whose root is `volumeRootFD`.
    static func delete(name: String, volumeRootFD fd: Int32) throws {
        if fs_snapshot_delete(fd, name, 0) != 0 {
            throw InfraError(operation: "fs_snapshot_delete", path: name, code: errno)
        }
    }

    /// Mount snapshot `name` (of the volume at `volumeRootFD`) read-only at `mountPath`.
    /// May fail with EPERM without elevated privileges — callers must handle that and fall back.
    static func mount(name: String, volumeRootFD fd: Int32, at mountPath: String) throws {
        if fs_snapshot_mount(fd, mountPath, name, 0) != 0 {
            throw InfraError(operation: "fs_snapshot_mount", path: mountPath, code: errno)
        }
    }
}
