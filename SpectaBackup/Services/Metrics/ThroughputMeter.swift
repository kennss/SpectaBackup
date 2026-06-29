//
//  @file        ThroughputMeter.swift
//  @description Measures backup write throughput from the engine's cumulative bytesCopied, smoothed
//               with an exponential moving average so the menu-bar rate doesn't jitter.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-06-29
//  @lastUpdated 2026-06-29
//

import Foundation

struct ThroughputMeter: Sendable {
    private var lastBytes: Int64 = 0
    private var lastTime: Date?
    private(set) var bytesPerSecond: Double = 0

    /// Feed the latest cumulative bytes-copied total and the current time.
    mutating func update(totalBytes: Int64, now: Date) {
        defer { lastBytes = totalBytes; lastTime = now }
        guard let lastTime else { return }
        let dt = now.timeIntervalSince(lastTime)
        guard dt > 0 else { return }
        let instant = Double(totalBytes - lastBytes) / dt
        bytesPerSecond = bytesPerSecond == 0 ? instant : bytesPerSecond * 0.7 + instant * 0.3
    }
}
