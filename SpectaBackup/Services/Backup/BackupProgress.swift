//
//  @file        BackupProgress.swift
//  @description Progress snapshot streamed from the engine to the UI during a backup pass: files
//               processed, bytes actually copied (drives throughput), and the current path.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-06-29
//  @lastUpdated 2026-06-29
//

import Foundation

struct BackupProgress: Sendable {
    var filesProcessed: Int = 0
    var bytesCopied: Int64 = 0
    var currentPath: String?
}
