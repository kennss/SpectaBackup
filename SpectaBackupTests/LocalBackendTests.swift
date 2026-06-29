//
//  @file        LocalBackendTests.swift
//  @description Tests for the filesystem object store: put/get round-trip, stat size, Range read,
//               prefix listing, and delete.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-06-30
//  @lastUpdated 2026-06-30
//

import XCTest
@testable import SpectaBackup

final class LocalBackendTests: XCTestCase {

    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sbk-backend-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    func testPutGetStatRoundTrip() async throws {
        let backend = try LocalBackend(root: tmp)
        let payload = Data("hello backend".utf8)
        try await backend.put(key: "data/ab/blob1", data: payload)

        let got = try await backend.get(key: "data/ab/blob1")
        XCTAssertEqual(got, payload)
        let stat = try await backend.stat(key: "data/ab/blob1")
        XCTAssertEqual(stat?.size, payload.count)
    }

    func testRangeRead() async throws {
        let backend = try LocalBackend(root: tmp)
        try await backend.put(key: "pack", data: Data("0123456789".utf8))
        let mid = try await backend.get(key: "pack", range: 3..<7)
        XCTAssertEqual(mid, Data("3456".utf8))
    }

    func testListAndDelete() async throws {
        let backend = try LocalBackend(root: tmp)
        try await backend.put(key: "data/aa/x", data: Data([1]))
        try await backend.put(key: "data/aa/y", data: Data([2]))
        try await backend.put(key: "snapshots/s1", data: Data([3]))

        let dataKeys = try await backend.list(prefix: "data")
        XCTAssertEqual(Set(dataKeys), ["data/aa/x", "data/aa/y"])

        try await backend.delete(key: "data/aa/x")
        let afterDelete = try await backend.stat(key: "data/aa/x")
        XCTAssertNil(afterDelete)
    }

    func testStatMissingIsNil() async throws {
        let backend = try LocalBackend(root: tmp)
        let stat = try await backend.stat(key: "does/not/exist")
        XCTAssertNil(stat)
    }
}
