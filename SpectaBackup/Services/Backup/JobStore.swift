//
//  @file        JobStore.swift
//  @description Persists the backup job list as JSON in Application Support. Small, human-readable
//               config only — snapshot history lives in each destination's SQLite catalog.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-06-29
//  @lastUpdated 2026-06-29
//

import Foundation

struct JobStore: Sendable {
    let fileURL: URL

    init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SpectaBackup", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("config.json")
    }

    func load() -> [BackupJob] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([BackupJob].self, from: data)) ?? []
    }

    func save(_ jobs: [BackupJob]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(jobs)
        try data.write(to: fileURL, options: .atomic)
    }
}
