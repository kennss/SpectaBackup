//
//  @file        Scheduler.swift
//  @description Pure interval-schedule math for interval-triggered jobs: convert an IntervalSpec to
//               seconds, decide whether a job is due (given its last backup time), and compute the
//               next-due date. The coordinator ticks periodically and calls isDue to fire runNow.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-06-29
//  @lastUpdated 2026-06-29
//
//  Notes:
//  - A job that has never backed up is always due (first run). preferredHour is reserved for a future
//    refinement (align daily/weekly runs to a time of day); M2 uses pure interval spacing.
//

import Foundation

enum Scheduler {
    static func interval(_ spec: IntervalSpec) -> TimeInterval {
        let unit: TimeInterval
        switch spec.unit {
        case .hours: unit = 3_600
        case .days:  unit = 86_400
        case .weeks: unit = 604_800
        }
        return Double(max(1, spec.count)) * unit
    }

    static func isDue(spec: IntervalSpec, lastBackup: Date?, now: Date) -> Bool {
        guard let lastBackup else { return true }
        return now.timeIntervalSince(lastBackup) >= interval(spec)
    }

    static func nextDue(spec: IntervalSpec, lastBackup: Date?) -> Date? {
        guard let lastBackup else { return nil }
        return lastBackup.addingTimeInterval(interval(spec))
    }
}
