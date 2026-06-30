//
//  @file        FastCDC.swift
//  @description Content-defined chunking (gear-based / FastCDC, normalized). Splits a byte stream
//               into variable-size chunks at content-derived boundaries so that an edit only changes
//               nearby chunks — the basis of deduplication. Deterministic for a given input.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-06-30
//  @lastUpdated 2026-06-30
//
//  Notes:
//  - Normalized chunking: a stricter mask (maskS) before the average size discourages early cuts;
//    a looser mask (maskL) after it encourages cuts before max — tightening the size distribution.
//  - The gear table is a fixed 256-entry table (deterministic). A per-repo chunker seed (to vary
//    boundaries per repo, per ENCRYPTION_DESIGN) can later perturb the rolling hash; not yet applied.
//

import Foundation

struct FastCDC: Sendable {
    let minSize: Int
    let avgSize: Int
    let maxSize: Int
    private let maskS: UInt64
    private let maskL: UInt64

    init(minSize: Int = 512 * 1024, avgSize: Int = 1024 * 1024, maxSize: Int = 8 * 1024 * 1024) {
        self.minSize = minSize
        self.avgSize = avgSize
        self.maxSize = maxSize
        let bits = UInt64(max(1, Int(log2(Double(avgSize)))))
        self.maskS = (UInt64(1) << (bits + 2)) - 1
        self.maskL = (UInt64(1) << (bits - 2)) - 1
    }

    /// Emit chunk byte-ranges of `data` in order.
    func chunk(_ data: Data, emit: (Range<Int>) -> Void) {
        let n = data.count
        guard n > 0 else { return }
        // Hoist the static gear table out of the byte loop: a `static let` is accessed via a
        // thread-safe once-check on every reference, which in unoptimized builds turns into a huge
        // per-byte cost on large files. Grab a pointer to it once.
        Self.gear.withUnsafeBufferPointer { gear in
            data.withUnsafeBytes { raw in
                let bytes = raw.bindMemory(to: UInt8.self)
                var start = 0
                while start < n {
                    let end = nextCut(bytes, start: start, count: n, gear: gear)
                    emit(start..<end)
                    start = end
                }
            }
        }
    }

    private func nextCut(_ bytes: UnsafeBufferPointer<UInt8>, start: Int, count n: Int,
                         gear: UnsafeBufferPointer<UInt64>) -> Int {
        let remaining = n - start
        if remaining <= minSize { return n }

        var fingerprint: UInt64 = 0
        var i = start + minSize                       // never cut before minSize
        let avgEnd = min(start + avgSize, n)
        let maxEnd = min(start + maxSize, n)

        while i < avgEnd {
            fingerprint = (fingerprint << 1) &+ gear[Int(bytes[i])]
            if (fingerprint & maskS) == 0 { return i + 1 }
            i += 1
        }
        while i < maxEnd {
            fingerprint = (fingerprint << 1) &+ gear[Int(bytes[i])]
            if (fingerprint & maskL) == 0 { return i + 1 }
            i += 1
        }
        return maxEnd
    }

    /// Fixed 256-entry gear table, generated deterministically (xorshift64) so chunking is stable.
    static let gear: [UInt64] = {
        var table = [UInt64](repeating: 0, count: 256)
        var x: UInt64 = 0x2545F4914F6CDD1D
        for i in 0..<256 {
            x ^= x >> 12; x ^= x << 25; x ^= x >> 27
            table[i] = x &* 0x2545F4914F6CDD1D
        }
        return table
    }()
}
