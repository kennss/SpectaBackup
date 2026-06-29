//
//  @file        BackupJob.swift
//  @description Core job model: one or more source folders → one destination, with a trigger mode,
//               exclude rules, and a retention policy. Persisted as JSON in Application Support.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-06-29
//  @lastUpdated 2026-06-29
//
//  Notes:
//  - `sources`/`destination` are absolute file URLs. The app is non-sandboxed, so no security-scoped
//    bookmarks are needed — paths are stored and used directly.
//  - TriggerMode is a Codable enum with an associated IntervalSpec; Swift synthesizes the coding.
//

import Foundation

/// How a backup job decides when to run.
enum TriggerMode: Codable, Sendable, Hashable {
    /// React to filesystem changes immediately (FSEvents + debounce).
    case realtime
    /// Run on a fixed time/date interval.
    case interval(IntervalSpec)
}

/// Unit for an interval-based trigger.
enum IntervalUnit: String, Codable, Sendable, Hashable, CaseIterable {
    case hours
    case days
    case weeks
}

/// A fixed schedule, e.g. every 6 hours, every 1 day at 02:00.
struct IntervalSpec: Codable, Sendable, Hashable {
    var unit: IntervalUnit
    /// Number of `unit`s between runs (>= 1).
    var count: Int
    /// Preferred hour of day (0–23) for daily/weekly runs; nil = no preference.
    var preferredHour: Int?

    init(unit: IntervalUnit, count: Int, preferredHour: Int? = nil) {
        self.unit = unit
        self.count = max(1, count)
        self.preferredHour = preferredHour
    }
}

/// A single backup job.
struct BackupJob: Codable, Sendable, Identifiable, Hashable {
    let id: UUID
    var name: String
    /// Absolute source folder URLs to back up.
    var sources: [URL]
    /// Destination root (local volume path or mounted NAS share).
    var destination: URL
    var trigger: TriggerMode
    /// Relative glob patterns to exclude, in addition to the built-in excludes.
    var excludeGlobs: [String]
    var retention: RetentionPolicy
    var isEnabled: Bool
    let createdAt: Date

    init(id: UUID = UUID(),
         name: String,
         sources: [URL],
         destination: URL,
         trigger: TriggerMode = .realtime,
         excludeGlobs: [String] = [],
         retention: RetentionPolicy = .automatic,
         isEnabled: Bool = true,
         createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.sources = sources
        self.destination = destination
        self.trigger = trigger
        self.excludeGlobs = excludeGlobs
        self.retention = retention
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }
}
