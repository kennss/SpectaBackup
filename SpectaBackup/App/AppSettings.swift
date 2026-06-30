//
//  @file        AppSettings.swift
//  @description App-wide settings. JobDefaults are the DEFAULT values applied to newly created backup
//               jobs (trigger / retention / encryption); each job can still override them in its own
//               settings. Persisted to UserDefaults as JSON.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-06-30
//  @lastUpdated 2026-06-30
//

import Foundation

/// Default settings a new backup job starts with.
struct JobDefaults: Codable, Sendable {
    var trigger: TriggerMode
    var retention: RetentionPolicy
    var encryptionEnabled: Bool

    init(trigger: TriggerMode = .realtime,
         retention: RetentionPolicy = .automatic,
         encryptionEnabled: Bool = false) {
        self.trigger = trigger
        self.retention = retention
        self.encryptionEnabled = encryptionEnabled
    }
}

@MainActor
@Observable
final class AppSettings {
    var jobDefaults: JobDefaults {
        didSet { persist() }
    }

    @ObservationIgnored private let storageKey = "spectabackup.jobDefaults"

    init() {
        if let data = UserDefaults.standard.data(forKey: "spectabackup.jobDefaults"),
           let decoded = try? JSONDecoder().decode(JobDefaults.self, from: data) {
            jobDefaults = decoded
        } else {
            jobDefaults = JobDefaults()
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(jobDefaults) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
