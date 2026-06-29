//
//  @file        FileWalker.swift
//  @description Recursive source-tree walker built on lstat (never follows symlinks). Yields a
//               FileEntry per item with the metadata the engine needs: type, size, mtime, and the
//               (dev, ino, nlink) identity used to detect and preserve intra-source hardlinks.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-06-29
//  @lastUpdated 2026-06-29
//
//  Notes:
//  - Uses lstat directly (not URLResourceValues) so we get exact (st_dev, st_ino, st_nlink, st_blocks)
//    and never accidentally follow a symlink into another tree.
//  - Directories are visited before their contents (pre-order) so the engine can mkdir parents first.
//  - Symlinks are yielded as leaf entries and never descended into.
//

import Darwin
import Foundation

struct FileEntry: Sendable {
    let url: URL
    /// Path relative to the source root (POSIX separators), e.g. "Docs/a.txt".
    let relativePath: String
    let isDirectory: Bool
    let isSymlink: Bool
    let size: Int64
    let mtime: Date
    let dev: dev_t
    let ino: ino_t
    let nlink: nlink_t
    /// Allocated 512-byte blocks (st_blocks) — used for honest "added bytes" accounting.
    let blocks: Int64

    /// True when this is a regular file referenced by more than one path (a hardlink).
    var isHardlinked: Bool { !isDirectory && !isSymlink && nlink > 1 }
}

enum FileWalker {

    /// Walk `root` recursively, invoking `visit` for every non-excluded entry (pre-order).
    static func walk(root: URL,
                     exclusions: BackupExclusions,
                     visit: (FileEntry) throws -> Void) throws {
        try recurse(dir: root, relBase: "", exclusions: exclusions, visit: visit)
    }

    private static func recurse(dir: URL,
                                relBase: String,
                                exclusions: BackupExclusions,
                                visit: (FileEntry) throws -> Void) throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        for name in names {
            let rel = relBase.isEmpty ? name : relBase + "/" + name
            if exclusions.isExcluded(relativePath: rel, name: name) { continue }
            let childURL = dir.appendingPathComponent(name)
            guard let entry = statEntry(url: childURL, relativePath: rel) else { continue }
            try visit(entry)
            if entry.isDirectory && !entry.isSymlink {
                try recurse(dir: childURL, relBase: rel, exclusions: exclusions, visit: visit)
            }
        }
    }

    private static func statEntry(url: URL, relativePath: String) -> FileEntry? {
        var st = Darwin.stat()
        guard lstat(url.path, &st) == 0 else { return nil }
        let kind = st.st_mode & S_IFMT
        let mtime = Date(timeIntervalSince1970:
            Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1_000_000_000)
        return FileEntry(
            url: url,
            relativePath: relativePath,
            isDirectory: kind == S_IFDIR,
            isSymlink: kind == S_IFLNK,
            size: Int64(st.st_size),
            mtime: mtime,
            dev: st.st_dev,
            ino: st.st_ino,
            nlink: st.st_nlink,
            blocks: Int64(st.st_blocks)
        )
    }
}
