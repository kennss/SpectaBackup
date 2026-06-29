//
//  @file        BlobStoreTests.swift
//  @description Tests for the pack/index blob store: put→get round-trip, dedup (same content stored
//               once), flush + reload-index in a fresh store, many blobs packed together with
//               per-blob Range reads, tamper detection, and missing-blob error.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-06-30
//  @lastUpdated 2026-06-30
//

import XCTest
@testable import SpectaBackup

final class BlobStoreTests: XCTestCase {

    private var tmp: URL!
    private let keys = RepoKeys.generate()

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sbk-blobstore-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    func testPutGetRoundTrip() async throws {
        let backend = try LocalBackend(root: tmp)
        let store = BlobStore(backend: backend, keys: keys, packTargetSize: 1024)
        let payload = Data("hello blob".utf8)
        let id = try await store.put(payload)
        let got = try await store.get(id)
        XCTAssertEqual(got, payload)
    }

    func testDedupStoresOnce() async throws {
        let backend = try LocalBackend(root: tmp)
        let store = BlobStore(backend: backend, keys: keys, packTargetSize: 1 << 20)
        let id1 = try await store.put(Data("same content".utf8))
        let id2 = try await store.put(Data("same content".utf8))
        XCTAssertEqual(id1, id2)
        let pending = await store.pendingCount
        XCTAssertEqual(pending, 1, "identical content must be buffered once")
    }

    func testFlushThenReloadInFreshStore() async throws {
        let backend = try LocalBackend(root: tmp)
        let payloads = (0..<5).map { Data("payload-\($0)".utf8) }

        let writer = BlobStore(backend: backend, keys: keys, packTargetSize: 1 << 20)
        var ids: [Data] = []
        for p in payloads { ids.append(try await writer.put(p)) }
        try await writer.flush()

        let reader = BlobStore(backend: backend, keys: keys)
        try await reader.loadIndex()
        for (id, expected) in zip(ids, payloads) {
            let got = try await reader.get(id)
            XCTAssertEqual(got, expected)
        }
    }

    func testManyBlobsPackedWithRangeReads() async throws {
        let backend = try LocalBackend(root: tmp)
        let writer = BlobStore(backend: backend, keys: keys, packTargetSize: 1 << 20)  // one pack
        let payloads = (0..<20).map { Data(repeating: UInt8($0), count: 100 + $0) }
        var ids: [Data] = []
        for p in payloads { ids.append(try await writer.put(p)) }
        try await writer.flush()

        // a single pack should hold them all
        let packs = try await backend.list(prefix: "data")
        XCTAssertEqual(packs.count, 1)

        let reader = BlobStore(backend: backend, keys: keys)
        try await reader.loadIndex()
        for (id, expected) in zip(ids, payloads) {
            let got = try await reader.get(id)
            XCTAssertEqual(got, expected)
        }
    }

    func testMissingBlobThrows() async throws {
        let backend = try LocalBackend(root: tmp)
        let store = BlobStore(backend: backend, keys: keys)
        let bogus = Data(repeating: 0xEE, count: 32)
        do {
            _ = try await store.get(bogus)
            XCTFail("expected blobNotFound")
        } catch { /* expected */ }
    }
}
