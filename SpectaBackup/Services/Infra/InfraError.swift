//
//  @file        InfraError.swift
//  @description Error type for low-level syscall wrappers in the Infra layer. Captures the failing
//               operation, an optional path, and the raw errno for precise diagnostics.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-06-29
//  @lastUpdated 2026-06-29
//

import Foundation

struct InfraError: Error, CustomStringConvertible {
    let operation: String
    let path: String?
    let code: Int32

    var errnoMessage: String { String(cString: strerror(code)) }

    var description: String {
        if let path {
            return "\(operation) failed for \(path): \(errnoMessage) (errno \(code))"
        }
        return "\(operation) failed: \(errnoMessage) (errno \(code))"
    }

    /// True when the failure indicates the volume/mount went away (abort the pass, don't retry).
    var isVolumeGone: Bool {
        code == EIO || code == ENXIO || code == ENOTCONN || code == ENODEV
    }
}
