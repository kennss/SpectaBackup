//
//  @file        RestoreEngineTests.swift
//  @description End-to-end restore tests: restore an earlier version of a file, recover a deleted
//               file from an old snapshot, and verify conflict policies (overwrite / skip / keepBoth)
//               — including that keep-both never destroys the existing file.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-06-29
//  @lastUpdated 2026-06-29
//

import XCTest
@testable import SpectaBackup

final class RestoreEngineTests: XCTestCase {

    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sbk-restore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    private func makeJob() throws -> (URL, BackupJob) {
        let source = tmp.appendingPathComponent("src", isDirectory: true)
        let dest = tmp.appendingPathComponent("dst", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        return (source, BackupJob(name: "t", sources: [source], destination: dest))
    }

    private func snapshotSourceRoot(_ job: BackupJob, _ rec: SnapshotRecord) -> URL {
        BackupRunner.jobRoot(for: job).appendingPathComponent("snapshots/\(rec.dirName)/src", isDirectory: true)
    }

    func testRestoreEarlierVersionToNewTarget() async throws {
        let (source, job) = try makeJob()
        let runner = BackupRunner()
        let file = source.appendingPathComponent("a.txt")

        try "v1".write(to: file, atomically: true, encoding: .utf8)
        let r1 = try await runner.run(job: job) { _ in }
        let s1 = try XCTUnwrap(r1.snapshot)
        try "v2-longer".write(to: file, atomically: true, encoding: .utf8)
        _ = try await runner.run(job: job) { _ in }   // s2

        let target = tmp.appendingPathComponent("restore-here", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

        let outcome = try RestoreEngine().restore(snapshotSourceRoot: snapshotSourceRoot(job, s1),
                                                  relPaths: ["a.txt"], to: target,
                                                  conflict: .overwrite, progress: { _ in })
        XCTAssertEqual(outcome.restored, 1)
        XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("a.txt"), encoding: .utf8), "v1")
    }

    func testRestoreDeletedFile() async throws {
        let (source, job) = try makeJob()
        let runner = BackupRunner()
        try "a".write(to: source.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "b".write(to: source.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        let r1 = try await runner.run(job: job) { _ in }
        let s1 = try XCTUnwrap(r1.snapshot)

        try FileManager.default.removeItem(at: source.appendingPathComponent("b.txt"))
        _ = try await runner.run(job: job) { _ in }   // s2 reflects deletion

        let target = tmp.appendingPathComponent("recovered", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        _ = try RestoreEngine().restore(snapshotSourceRoot: snapshotSourceRoot(job, s1),
                                        relPaths: ["b.txt"], to: target,
                                        conflict: .overwrite, progress: { _ in })
        XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("b.txt"), encoding: .utf8), "b")
    }

    func testKeepBothNeverDestroysExisting() async throws {
        let (source, job) = try makeJob()
        let runner = BackupRunner()
        try "snapshot-version".write(to: source.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let r1 = try await runner.run(job: job) { _ in }
        let s1 = try XCTUnwrap(r1.snapshot)

        // Target already has a different a.txt — keepBoth must preserve it.
        let target = tmp.appendingPathComponent("target", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try "existing-precious".write(to: target.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

        let outcome = try RestoreEngine().restore(snapshotSourceRoot: snapshotSourceRoot(job, s1),
                                                  relPaths: ["a.txt"], to: target,
                                                  conflict: .keepBoth, progress: { _ in })
        XCTAssertEqual(outcome.restored, 1)
        // Original untouched
        XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("a.txt"), encoding: .utf8), "existing-precious")
        // Restored copy alongside
        XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("a (restored).txt"), encoding: .utf8), "snapshot-version")
    }

    func testSkipLeavesExisting() async throws {
        let (source, job) = try makeJob()
        let runner = BackupRunner()
        try "snap".write(to: source.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let r1 = try await runner.run(job: job) { _ in }
        let s1 = try XCTUnwrap(r1.snapshot)

        let target = tmp.appendingPathComponent("target", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try "keep-me".write(to: target.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

        let outcome = try RestoreEngine().restore(snapshotSourceRoot: snapshotSourceRoot(job, s1),
                                                  relPaths: ["a.txt"], to: target,
                                                  conflict: .skip, progress: { _ in })
        XCTAssertEqual(outcome.skipped, 1)
        XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("a.txt"), encoding: .utf8), "keep-me")
    }
}
