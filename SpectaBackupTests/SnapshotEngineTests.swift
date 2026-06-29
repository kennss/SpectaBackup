//
//  @file        SnapshotEngineTests.swift
//  @description Engine safety tests on the boot APFS volume's temp dir: clone immutability (a prior
//               snapshot is never mutated by a later one), incremental change detection, deletion
//               reflection with history kept, empty-snapshot skipping, intra-source hardlink
//               preservation, and metadata/symlink round-trip.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-06-29
//  @lastUpdated 2026-06-29
//

import XCTest
import Darwin
@testable import SpectaBackup

final class SnapshotEngineTests: XCTestCase {

    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("spectabackup-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    // MARK: - Fixtures

    private func cloneCaps() -> DestinationCapabilities {
        DestinationCapabilities(fileSystem: .apfs, supportsClone: true, supportsHardlink: true,
                                hardlinkPersistsRemount: true, xattrRoundTrip: true,
                                isCaseSensitive: false, mtimeResolution: .nanosecond,
                                freeBytes: 1 << 40, probedAt: Date())
    }

    /// Capabilities that select the hardlink-tree strategy (no clonefile; persistent hardlinks).
    private func hardlinkCaps() -> DestinationCapabilities {
        DestinationCapabilities(fileSystem: .other, supportsClone: false, supportsHardlink: true,
                                hardlinkPersistsRemount: true, xattrRoundTrip: true,
                                isCaseSensitive: false, mtimeResolution: .nanosecond,
                                freeBytes: 1 << 40, probedAt: Date())
    }

    private func makeFixture() throws -> (engine: SnapshotEngine, job: BackupJob, jobRoot: URL, source: URL) {
        let source = tmp.appendingPathComponent("src", isDirectory: true)
        let dest = tmp.appendingPathComponent("dst", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let job = BackupJob(name: "test", sources: [source], destination: dest)
        let jobRoot = dest.appendingPathComponent("SpectaBackup/\(job.id.uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: jobRoot, withIntermediateDirectories: true)
        let catalog = try CatalogStore(path: jobRoot.appendingPathComponent("catalog.sqlite").path)
        return (SnapshotEngine(catalog: catalog), job, jobRoot, source)
    }

    private func snapshotFile(_ jobRoot: URL, _ rec: SnapshotRecord, _ source: URL, _ rel: String) -> URL {
        jobRoot.appendingPathComponent("snapshots/\(rec.dirName)/\(source.lastPathComponent)/\(rel)")
    }

    // MARK: - Tests

    func testFullThenIncrementalKeepsImmutableHistory() async throws {
        let f = try makeFixture()
        let file = f.source.appendingPathComponent("a.txt")
        try "v1".write(to: file, atomically: true, encoding: .utf8)

        let s1 = try await XCTUnwrapAsync(f.engine.runPass(job: f.job, jobRoot: f.jobRoot, caps: cloneCaps()) { _ in })
        XCTAssertEqual(try String(contentsOf: snapshotFile(f.jobRoot, s1, f.source, "a.txt"), encoding: .utf8), "v1")

        // Change content (different size ⇒ unambiguously detected).
        try "v2-longer".write(to: file, atomically: true, encoding: .utf8)
        let s2 = try await XCTUnwrapAsync(f.engine.runPass(job: f.job, jobRoot: f.jobRoot, caps: cloneCaps()) { _ in })

        XCTAssertEqual(try String(contentsOf: snapshotFile(f.jobRoot, s2, f.source, "a.txt"), encoding: .utf8), "v2-longer")
        // The earlier snapshot must remain untouched (CoW clone isolation).
        XCTAssertEqual(try String(contentsOf: snapshotFile(f.jobRoot, s1, f.source, "a.txt"), encoding: .utf8), "v1")
    }

    func testDeletionReflectedButHistoryKept() async throws {
        let f = try makeFixture()
        try "a".write(to: f.source.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "b".write(to: f.source.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        let s1 = try await XCTUnwrapAsync(f.engine.runPass(job: f.job, jobRoot: f.jobRoot, caps: cloneCaps()) { _ in })

        try FileManager.default.removeItem(at: f.source.appendingPathComponent("b.txt"))
        let s2 = try await XCTUnwrapAsync(f.engine.runPass(job: f.job, jobRoot: f.jobRoot, caps: cloneCaps()) { _ in })

        XCTAssertTrue(FileManager.default.fileExists(atPath: snapshotFile(f.jobRoot, s2, f.source, "a.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: snapshotFile(f.jobRoot, s2, f.source, "b.txt").path))
        // Deleted file still recoverable from the earlier snapshot.
        XCTAssertTrue(FileManager.default.fileExists(atPath: snapshotFile(f.jobRoot, s1, f.source, "b.txt").path))
    }

    func testEmptyIncrementalIsSkipped() async throws {
        let f = try makeFixture()
        try "x".write(to: f.source.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        _ = try await XCTUnwrapAsync(f.engine.runPass(job: f.job, jobRoot: f.jobRoot, caps: cloneCaps()) { _ in })

        // No changes → second pass produces no snapshot.
        let s2 = try await f.engine.runPass(job: f.job, jobRoot: f.jobRoot, caps: cloneCaps()) { _ in }
        XCTAssertNil(s2)
    }

    func testIntraSourceHardlinkPreserved() async throws {
        let f = try makeFixture()
        let orig = f.source.appendingPathComponent("orig.bin")
        try Data([1, 2, 3, 4]).write(to: orig)
        try Syscalls.hardlink(from: orig.path, to: f.source.appendingPathComponent("link.bin").path)

        let s = try await XCTUnwrapAsync(f.engine.runPass(job: f.job, jobRoot: f.jobRoot, caps: cloneCaps()) { _ in })
        let a = snapshotFile(f.jobRoot, s, f.source, "orig.bin").path
        let b = snapshotFile(f.jobRoot, s, f.source, "link.bin").path
        var sa = Darwin.stat(), sb = Darwin.stat()
        XCTAssertEqual(lstat(a, &sa), 0)
        XCTAssertEqual(lstat(b, &sb), 0)
        XCTAssertEqual(sa.st_ino, sb.st_ino, "backed-up hardlink pair should share one inode")
        XCTAssertGreaterThan(sa.st_nlink, 1)
    }

    func testMetadataAndSymlinkPreserved() async throws {
        let f = try makeFixture()
        let file = f.source.appendingPathComponent("data.bin")
        try Data([0xDE, 0xAD]).write(to: file)
        // custom perms + xattr
        chmod(file.path, 0o640)
        let xname = "com.calidalab.spectabackup.kind"
        let xval: [UInt8] = [0x42]
        _ = xval.withUnsafeBytes { setxattr(file.path, xname, $0.baseAddress, $0.count, 0, 0) }
        // symlink
        try FileManager.default.createSymbolicLink(atPath: f.source.appendingPathComponent("link").path,
                                                   withDestinationPath: "data.bin")

        let s = try await XCTUnwrapAsync(f.engine.runPass(job: f.job, jobRoot: f.jobRoot, caps: cloneCaps()) { _ in })
        let backedFile = snapshotFile(f.jobRoot, s, f.source, "data.bin").path
        let backedLink = snapshotFile(f.jobRoot, s, f.source, "link").path

        // perms preserved
        var st = Darwin.stat()
        XCTAssertEqual(lstat(backedFile, &st), 0)
        XCTAssertEqual(st.st_mode & 0o777, 0o640)
        // xattr preserved
        var buf = [UInt8](repeating: 0, count: 4)
        let n = buf.withUnsafeMutableBytes { getxattr(backedFile, xname, $0.baseAddress, $0.count, 0, 0) }
        XCTAssertEqual(n, 1)
        XCTAssertEqual(buf[0], 0x42)
        // symlink copied as a link, not followed
        XCTAssertEqual(lstat(backedLink, &st), 0)
        XCTAssertEqual(st.st_mode & S_IFMT, S_IFLNK)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: backedLink), "data.bin")
    }

    func testDestinationProbeReportsAPFSClone() throws {
        let dest = tmp.appendingPathComponent("probe", isDirectory: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let caps = try DestinationProbe.probe(destination: dest)
        XCTAssertEqual(caps.fileSystem, .apfs)
        XCTAssertTrue(caps.supportsClone)
        XCTAssertEqual(caps.strategy, .clone)
    }

    func testHardlinkTreeSharesUnchangedKeepsHistory() async throws {
        let f = try makeFixture()
        try "a-v1".write(to: f.source.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "b-stable".write(to: f.source.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        let s1 = try await XCTUnwrapAsync(f.engine.runPass(job: f.job, jobRoot: f.jobRoot, caps: hardlinkCaps()) { _ in })

        // Change a.txt (different size ⇒ detected); leave b.txt untouched.
        try "a-v2-longer".write(to: f.source.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let s2 = try await XCTUnwrapAsync(f.engine.runPass(job: f.job, jobRoot: f.jobRoot, caps: hardlinkCaps()) { _ in })

        // History immutable.
        XCTAssertEqual(try String(contentsOf: snapshotFile(f.jobRoot, s1, f.source, "a.txt"), encoding: .utf8), "a-v1")
        XCTAssertEqual(try String(contentsOf: snapshotFile(f.jobRoot, s2, f.source, "a.txt"), encoding: .utf8), "a-v2-longer")

        // Unchanged file is shared via a hardlink across snapshots (one inode).
        var ino1 = Darwin.stat(), ino2 = Darwin.stat()
        XCTAssertEqual(lstat(snapshotFile(f.jobRoot, s1, f.source, "b.txt").path, &ino1), 0)
        XCTAssertEqual(lstat(snapshotFile(f.jobRoot, s2, f.source, "b.txt").path, &ino2), 0)
        XCTAssertEqual(ino1.st_ino, ino2.st_ino, "unchanged file should be hardlinked across snapshots")

        // Changed file must be a fresh, independent inode (never write-in-place on a shared link).
        var a1 = Darwin.stat(), a2 = Darwin.stat()
        XCTAssertEqual(lstat(snapshotFile(f.jobRoot, s1, f.source, "a.txt").path, &a1), 0)
        XCTAssertEqual(lstat(snapshotFile(f.jobRoot, s2, f.source, "a.txt").path, &a2), 0)
        XCTAssertNotEqual(a1.st_ino, a2.st_ino, "changed file must be a fresh copy, not a mutated shared inode")
    }

    // MARK: - Async helper

    /// XCTUnwrap for an async-produced optional.
    private func XCTUnwrapAsync<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) throws -> T {
        try XCTUnwrap(value, file: file, line: line)
    }
}
