//
//  @file        DedupEngineTests.swift
//  @description End-to-end tests for the encrypted dedup engine: back up a source tree (files,
//               subdirectory, multi-chunk large file, symlink) then restore it in a fresh engine and
//               compare bytes/structure; and verify an unchanged re-backup reuses content-addressed
//               trees (no new tree objects).
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-06-30
//  @lastUpdated 2026-06-30
//

import XCTest
@testable import SpectaBackup

final class DedupEngineTests: XCTestCase {

    private var tmp: URL!
    private let keys = RepoKeys.generate()

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sbk-engine-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    private func makeEngine(_ repo: URL) throws -> DedupEngine {
        DedupEngine(backend: try LocalBackend(root: repo), keys: keys,
                    chunker: FastCDC(minSize: 64, avgSize: 256, maxSize: 1024))
    }

    private let bigFile = Data((0..<5000).map { UInt8($0 % 251) })

    private func buildSource() throws -> URL {
        let src = tmp.appendingPathComponent("src")
        let sub = src.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try Data("alpha".utf8).write(to: src.appendingPathComponent("a.txt"))
        try bigFile.write(to: sub.appendingPathComponent("big.bin"))
        try FileManager.default.createSymbolicLink(
            atPath: src.appendingPathComponent("link").path, withDestinationPath: "a.txt")
        return src
    }

    func testBackupRestoreRoundTrip() async throws {
        let src = try buildSource()
        let repo = tmp.appendingPathComponent("repo")

        let writer = try makeEngine(repo)
        let snapshot = try await writer.backUp(sources: [src], snapshotID: "s1", now: 1000)
        XCTAssertEqual(snapshot.fileCount, 2)

        let dst = tmp.appendingPathComponent("dst")
        let reader = try makeEngine(repo)
        try await reader.restore(snapshotID: "s1", to: dst)

        // Each source is restored under a subdirectory named after its lastPathComponent ("src").
        XCTAssertEqual(try Data(contentsOf: dst.appendingPathComponent("src/a.txt")), Data("alpha".utf8))
        XCTAssertEqual(try Data(contentsOf: dst.appendingPathComponent("src/sub/big.bin")), bigFile)
        let linkTarget = try FileManager.default.destinationOfSymbolicLink(
            atPath: dst.appendingPathComponent("src/link").path)
        XCTAssertEqual(linkTarget, "a.txt")
    }

    func testUnchangedReBackupReusesTrees() async throws {
        let src = try buildSource()
        let repo = tmp.appendingPathComponent("repo")
        let backend = try LocalBackend(root: repo)
        let engine = DedupEngine(backend: backend, keys: keys,
                                 chunker: FastCDC(minSize: 64, avgSize: 256, maxSize: 1024))

        _ = try await engine.backUp(sources: [src], snapshotID: "s1", now: 1000)
        let treesAfterFirst = try await backend.list(prefix: "trees").count

        _ = try await engine.backUp(sources: [src], snapshotID: "s2", now: 2000)
        let treesAfterSecond = try await backend.list(prefix: "trees").count

        XCTAssertEqual(treesAfterFirst, treesAfterSecond, "unchanged dirs must reuse content-addressed trees")
        XCTAssertGreaterThan(treesAfterFirst, 0)
    }
}
