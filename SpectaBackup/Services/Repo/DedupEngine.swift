//
//  @file        DedupEngine.swift
//  @description The encrypted dedup backup/restore engine. backUp() walks the job's source trees
//               (each becomes a named subtree under one root), chunks each file (FastCDC), stores
//               chunks as deduplicated blobs (BlobStore), builds content-addressed tree objects
//               (unchanged directories reuse their tree), and writes the snapshot last. restore()
//               reads snapshot → trees → reassembles each file from its blobs and writes it
//               atomically (temp + rename), never overwriting in place.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-06-30
//  @lastUpdated 2026-06-30
//
//  Note: files are currently read whole before chunking; streaming large files through FastCDC is a
//  later optimization (tracked separately), not a correctness concern for the engine shape.
//

import CryptoKit
import Foundation

struct DedupEngine: Sendable {
    private let backend: Backend
    private let blobStore: BlobStore
    private let cipher: BlobCipher
    private let chunker: FastCDC

    init(backend: Backend, keys: RepoKeys, chunker: FastCDC) {
        self.backend = backend
        self.blobStore = BlobStore(backend: backend, keys: keys)
        self.cipher = BlobCipher(keys: keys)
        self.chunker = chunker
    }

    /// Load the blob index (needed before restoring into a freshly-opened engine).
    func open() async throws {
        try await blobStore.loadIndex()
    }

    // MARK: - Backup

    /// Back up one or more source folders into a single snapshot. Each source becomes a named
    /// subdirectory (by `lastPathComponent`) under the snapshot's root tree.
    @discardableResult
    func backUp(sources: [URL], snapshotID: String, now: Double) async throws -> Snapshot {
        var rootNodes: [TreeNode] = []
        var fileCount = 0
        var totalBytes = 0
        for source in sources {
            let child = try await backUpDirectory(source)
            rootNodes.append(TreeNode(kind: .directory, name: source.lastPathComponent, treeID: child.treeID))
            fileCount += child.fileCount
            totalBytes += child.bytes
        }
        let rootTreeID = try await writeTree(rootNodes)
        try await blobStore.flush()

        let snapshot = Snapshot(rootTreeID: rootTreeID,
                                sourcePath: sources.map(\.path).joined(separator: ", "),
                                createdAt: now, fileCount: fileCount, totalBytes: totalBytes)
        let sealed = try cipher.sealMetadata(try JSONEncoder().encode(snapshot),
                                             context: "snapshots/\(snapshotID)")
        try await backend.put(key: "snapshots/\(snapshotID)", data: sealed)
        return snapshot
    }

    private func backUpDirectory(_ dir: URL) async throws -> (treeID: String, fileCount: Int, bytes: Int) {
        let entries = try FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var nodes: [TreeNode] = []
        var fileCount = 0
        var bytes = 0

        for entry in entries {
            let name = entry.lastPathComponent
            let rv = try entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])

            if rv.isSymbolicLink == true {
                let target = try FileManager.default.destinationOfSymbolicLink(atPath: entry.path)
                nodes.append(TreeNode(kind: .symlink, name: name, target: target))
            } else if rv.isDirectory == true {
                let child = try await backUpDirectory(entry)
                nodes.append(TreeNode(kind: .directory, name: name, treeID: child.treeID))
                fileCount += child.fileCount
                bytes += child.bytes
            } else {
                let data = try Data(contentsOf: entry)   // TODO: stream large files through FastCDC
                var ranges: [Range<Int>] = []
                chunker.chunk(data) { ranges.append($0) }
                var blobs: [Data] = []
                for range in ranges { blobs.append(try await blobStore.put(data.subdata(in: range))) }

                let attrs = try FileManager.default.attributesOfItem(atPath: entry.path)
                nodes.append(TreeNode(kind: .file, name: name, blobs: blobs, size: data.count,
                                      mode: (attrs[.posixPermissions] as? NSNumber)?.uint16Value,
                                      mtime: (attrs[.modificationDate] as? Date)?.timeIntervalSince1970))
                fileCount += 1
                bytes += data.count
            }
        }

        let treeID = try await writeTree(nodes)
        return (treeID, fileCount, bytes)
    }

    /// Serialize, encrypt, and store a tree (content-addressed → an identical tree is stored once).
    private func writeTree(_ nodes: [TreeNode]) async throws -> String {
        let treeData = try JSONEncoder().encode(nodes)
        let treeID = Self.hashHex(treeData)
        let key = "trees/\(treeID.prefix(2))/\(treeID)"
        if ((try? await backend.stat(key: key)) ?? nil) == nil {
            try await backend.put(key: key, data: try cipher.sealMetadata(treeData, context: "trees/\(treeID)"))
        }
        return treeID
    }

    // MARK: - Restore

    func restore(snapshotID: String, to destination: URL) async throws {
        try await blobStore.loadIndex()
        let sealed = try await backend.get(key: "snapshots/\(snapshotID)")
        let snapshot = try JSONDecoder().decode(
            Snapshot.self, from: cipher.openMetadata(sealed, context: "snapshots/\(snapshotID)"))
        try await restoreTree(snapshot.rootTreeID, to: destination)
    }

    private func restoreTree(_ treeID: String, to dir: URL) async throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let key = "trees/\(treeID.prefix(2))/\(treeID)"
        let sealed = try await backend.get(key: key)
        let nodes = try JSONDecoder().decode(
            [TreeNode].self, from: cipher.openMetadata(sealed, context: "trees/\(treeID)"))

        for node in nodes {
            let target = dir.appendingPathComponent(node.name)
            switch node.kind {
            case .directory:
                try await restoreTree(node.treeID ?? "", to: target)

            case .symlink:
                try? FileManager.default.removeItem(at: target)
                try FileManager.default.createSymbolicLink(atPath: target.path,
                                                           withDestinationPath: node.target ?? "")

            case .file:
                var data = Data()
                for blobID in node.blobs ?? [] { data.append(try await blobStore.get(blobID)) }
                // Atomic: write a temp sibling then rename over — never overwrite the target in place.
                let tmp = dir.appendingPathComponent(".restore-\(UUID().uuidString)")
                try data.write(to: tmp)
                _ = try? FileManager.default.removeItem(at: target)
                try FileManager.default.moveItem(at: tmp, to: target)
                if let mode = node.mode {
                    try? FileManager.default.setAttributes([.posixPermissions: NSNumber(value: mode)],
                                                           ofItemAtPath: target.path)
                }
            }
        }
    }

    private static func hashHex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
