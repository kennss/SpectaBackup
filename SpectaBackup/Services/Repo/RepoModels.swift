//
//  @file        RepoModels.swift
//  @description Object model for the encrypted dedup repo. A TreeNode is one directory entry (file
//               with its ordered chunk blob IDs, a subdirectory by content-addressed tree ID, or a
//               symlink). A Snapshot points at the root tree plus metadata and is written last.
//               Trees/snapshots are stored as encrypted metadata objects.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-06-30
//  @lastUpdated 2026-06-30
//

import Foundation

struct TreeNode: Codable, Sendable {
    enum Kind: String, Codable, Sendable { case file, directory, symlink }

    let kind: Kind
    let name: String

    // file
    var blobs: [Data]?      // ordered chunk blob IDs
    var size: Int?
    var mode: UInt16?       // posix permissions
    var mtime: Double?      // seconds since 1970

    // directory
    var treeID: String?     // content-addressed child tree

    // symlink
    var target: String?
}

struct Snapshot: Codable, Sendable {
    let rootTreeID: String
    let sourcePath: String
    let createdAt: Double   // seconds since 1970
    let fileCount: Int
    let totalBytes: Int     // sum of logical file sizes
}
