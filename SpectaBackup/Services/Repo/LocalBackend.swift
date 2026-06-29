//
//  @file        LocalBackend.swift
//  @description Filesystem-backed object store — the dedup engine's reference backend and the store
//               for local / external-disk / mounted-NAS encrypted repos. Strongly consistent and
//               supports Range reads, so it isolates engine bugs from cloud-backend quirks.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-06-30
//  @lastUpdated 2026-06-30
//

import Foundation

struct LocalBackend: Backend {
    let root: URL

    var capabilities: BackendCapabilities {
        BackendCapabilities(supportsRange: true, isStronglyConsistent: true,
                            maxObjectSize: .max, dailyUploadCap: 0, permanentDeleteRequired: false)
    }

    init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func url(_ key: String) -> URL { root.appendingPathComponent(key) }

    func put(key: String, data: Data) async throws {
        let dst = url(key)
        try FileManager.default.createDirectory(at: dst.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: dst, options: .atomic)   // .atomic = temp + rename
    }

    func get(key: String) async throws -> Data {
        try Data(contentsOf: url(key))
    }

    func get(key: String, range: Range<Int>) async throws -> Data {
        let handle = try FileHandle(forReadingFrom: url(key))
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(range.lowerBound))
        return try handle.read(upToCount: range.count) ?? Data()
    }

    func stat(key: String) async throws -> BackendStat? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url(key).path),
              let size = attrs[.size] as? Int else { return nil }
        return BackendStat(size: size)
    }

    func list(prefix: String) async throws -> [String] {
        // Enumerate by relative path (avoids /var ↔ /private/var symlink mismatches in absolute paths).
        let basePath = (prefix.isEmpty ? root : url(prefix)).path
        guard let enumerator = FileManager.default.enumerator(atPath: basePath) else { return [] }
        var keys: [String] = []
        while let relative = enumerator.nextObject() as? String {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: (basePath as NSString).appendingPathComponent(relative),
                                           isDirectory: &isDir)
            if isDir.boolValue { continue }
            keys.append(prefix.isEmpty ? relative : (prefix as NSString).appendingPathComponent(relative))
        }
        return keys
    }

    func delete(key: String) async throws {
        try? FileManager.default.removeItem(at: url(key))
    }
}
