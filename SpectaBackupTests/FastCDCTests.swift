//
//  @file        FastCDCTests.swift
//  @description Tests for the content-defined chunker: deterministic boundaries, contiguous full
//               coverage, size bounds, and the core dedup property — inserting bytes near the start
//               re-syncs so most trailing chunks stay byte-identical.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-06-30
//  @lastUpdated 2026-06-30
//

import XCTest
@testable import SpectaBackup

final class FastCDCTests: XCTestCase {

    /// Deterministic pseudo-random bytes (xorshift64) so tests are stable.
    private func makeData(_ count: Int, seed: UInt64) -> Data {
        var x = seed == 0 ? 1 : seed
        var data = Data(capacity: count)
        for _ in 0..<count {
            x ^= x >> 12; x ^= x << 25; x ^= x >> 27
            data.append(UInt8(truncatingIfNeeded: x))
        }
        return data
    }

    private func chunks(_ cdc: FastCDC, _ data: Data) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        cdc.chunk(data) { ranges.append($0) }
        return ranges
    }

    func testDeterministicAndContiguous() {
        let cdc = FastCDC(minSize: 64, avgSize: 256, maxSize: 1024)
        let data = makeData(20_000, seed: 1)
        let a = chunks(cdc, data)
        let b = chunks(cdc, data)
        XCTAssertEqual(a, b)                              // deterministic
        XCTAssertEqual(a.first?.lowerBound, 0)
        XCTAssertEqual(a.last?.upperBound, data.count)    // covers the whole input
        for i in 1..<a.count { XCTAssertEqual(a[i].lowerBound, a[i - 1].upperBound) }  // contiguous
    }

    func testSizeBounds() {
        let cdc = FastCDC(minSize: 64, avgSize: 256, maxSize: 1024)
        let cs = chunks(cdc, makeData(20_000, seed: 2))
        for (i, range) in cs.enumerated() {
            XCTAssertLessThanOrEqual(range.count, 1024)
            if i < cs.count - 1 { XCTAssertGreaterThanOrEqual(range.count, 64) }  // last may be smaller
        }
    }

    func testEditResyncsMostChunks() {
        let cdc = FastCDC(minSize: 64, avgSize: 256, maxSize: 1024)
        let base = makeData(20_000, seed: 3)
        var edited = base
        edited.insert(contentsOf: Data(repeating: 0xAB, count: 10), at: 100)  // small insert near start

        let baseBlobs = Set(chunks(cdc, base).map { base.subdata(in: $0) })
        let editBlobs = chunks(cdc, edited).map { edited.subdata(in: $0) }
        let shared = editBlobs.filter { baseBlobs.contains($0) }.count
        XCTAssertGreaterThan(shared, editBlobs.count / 2,
                             "CDC must re-sync so the majority of chunks are unchanged (dedup)")
    }
}
