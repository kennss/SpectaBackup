//
//  @file        SnapshotBrowser.swift
//  @description Reads one snapshot's source-root tree on demand (one directory level per call) for
//               the restore UI, so browsing a huge snapshot never loads the whole tree at once.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-06-29
//  @lastUpdated 2026-06-29
//

import Darwin
import Foundation

struct SnapshotEntry: Identifiable, Sendable, Hashable {
    /// Path relative to the snapshot's source-root (POSIX separators).
    let relPath: String
    let name: String
    let isDirectory: Bool
    var id: String { relPath }
}

struct SnapshotBrowser: Sendable {
    /// .../snapshots/<dirName>/<sourceName>
    let sourceRoot: URL

    /// Immediate children under `relPath` ("" = root), directories first then case-insensitive name.
    func children(of relPath: String) -> [SnapshotEntry] {
        let dir = relPath.isEmpty ? sourceRoot : sourceRoot.appendingPathComponent(relPath)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        var entries: [SnapshotEntry] = []
        for name in names where name != SnapshotEngine.completeMarker {
            let childRel = relPath.isEmpty ? name : relPath + "/" + name
            var st = Darwin.stat()
            guard lstat(dir.appendingPathComponent(name).path, &st) == 0 else { continue }
            let isDir = (st.st_mode & S_IFMT) == S_IFDIR
            entries.append(SnapshotEntry(relPath: childRel, name: name, isDirectory: isDir))
        }
        return entries.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory && !b.isDirectory }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
}
