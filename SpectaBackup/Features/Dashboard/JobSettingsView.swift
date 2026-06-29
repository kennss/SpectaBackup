//
//  @file        JobSettingsView.swift
//  @description Edit a job's trigger (realtime vs interval), retention policy, and storage limits
//               (max backup size / minimum free space). Custom grouped-card layout for a clean,
//               aligned look. Saving persists via the coordinator and restarts watcher/schedule.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-06-29
//  @lastUpdated 2026-06-29
//
//  Notes:
//  - Sizes are entered in GB (decimal, 1 GB = 1,000,000,000 bytes); 0 means "no limit".
//

import SwiftUI

struct JobSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let job: BackupJob

    @State private var isRealtime: Bool
    @State private var intervalCount: Int
    @State private var intervalUnit: IntervalUnit
    @State private var retentionKind: RetentionKind
    @State private var keepValue: Int
    @State private var quotaGB: Double
    @State private var minFreeGB: Double

    private static let bytesPerGB: Double = 1_000_000_000

    enum RetentionKind: String, CaseIterable, Identifiable {
        case automatic, keepCount, keepDays, keepAll
        var id: String { rawValue }
        var label: String {
            switch self {
            case .automatic: return "Automatic (Time Machine style)"
            case .keepCount: return "Keep last N snapshots"
            case .keepDays: return "Keep last N days"
            case .keepAll: return "Keep all"
            }
        }
    }

    init(job: BackupJob) {
        self.job = job
        if case .interval(let spec) = job.trigger {
            _isRealtime = State(initialValue: false)
            _intervalCount = State(initialValue: spec.count)
            _intervalUnit = State(initialValue: spec.unit)
        } else {
            _isRealtime = State(initialValue: true)
            _intervalCount = State(initialValue: 1)
            _intervalUnit = State(initialValue: .days)
        }
        switch job.retention.mode {
        case .automatic: _retentionKind = State(initialValue: .automatic); _keepValue = State(initialValue: 30)
        case .keepCount(let n): _retentionKind = State(initialValue: .keepCount); _keepValue = State(initialValue: n)
        case .keepDays(let d): _retentionKind = State(initialValue: .keepDays); _keepValue = State(initialValue: d)
        case .keepAll: _retentionKind = State(initialValue: .keepAll); _keepValue = State(initialValue: 30)
        }
        _quotaGB = State(initialValue: Double(job.retention.maxTotalBytes) / Self.bytesPerGB)
        _minFreeGB = State(initialValue: Double(job.retention.minimumFreeBytes) / Self.bytesPerGB)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    whenSection
                    keepSection
                    storageSection
                }
                .padding(20)
            }
        }
        .frame(width: 500, height: 540)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "gearshape.fill").foregroundStyle(Color.wpDesignYellow)
            Text(job.name).font(.headline)
            Text("Settings").font(.headline).foregroundStyle(.secondary)
            Spacer()
            Button("Cancel") { dismiss() }
            Button("Save") { save() }
                .buttonStyle(.borderedProminent).tint(Color.wpDesignYellow).foregroundStyle(.black)
        }
        .padding(16)
    }

    // MARK: - Sections

    private var whenSection: some View {
        section("When to back up") {
            row("Trigger") {
                Picker("", selection: $isRealtime) {
                    Text("Realtime").tag(true)
                    Text("Schedule").tag(false)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 200)
            }
            if !isRealtime {
                rowDivider
                row("Run every") {
                    HStack(spacing: 10) {
                        Stepper("\(intervalCount)", value: $intervalCount, in: 1...365).fixedSize()
                        Picker("", selection: $intervalUnit) {
                            ForEach(IntervalUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .labelsHidden().frame(width: 100)
                    }
                }
            }
        }
    }

    private var keepSection: some View {
        section("Keep snapshots") {
            row("Retention") {
                Picker("", selection: $retentionKind) {
                    ForEach(RetentionKind.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden().frame(width: 250)
            }
            if retentionKind == .keepCount || retentionKind == .keepDays {
                rowDivider
                row(retentionKind == .keepCount ? "Number to keep" : "Days to keep") {
                    Stepper("\(keepValue)", value: $keepValue, in: 1...3650).fixedSize()
                }
            }
        }
    }

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            section("Storage limits") {
                numberRow("Max backup size", hint: "0 = unlimited", value: $quotaGB)
                rowDivider
                numberRow("Keep free space", hint: "0 = off", value: $minFreeGB)
            }
            Text("When a limit is reached, the oldest snapshots are deleted first — useful for a NAS share allowance.")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 4)
        }
    }

    // MARK: - Building blocks

    @ViewBuilder
    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.leading, 4)
            VStack(spacing: 0) { content() }.cardSurface()
        }
    }

    private func row<C: View>(_ label: String, @ViewBuilder _ control: () -> C) -> some View {
        HStack {
            Text(label)
            Spacer()
            control()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func numberRow(_ label: String, hint: String, value: Binding<Double>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                Text(hint).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            TextField("", value: value, format: .number)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
            Text("GB").foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var rowDivider: some View { Divider().padding(.leading, 14) }

    // MARK: - Save

    private func save() {
        var updated = job
        updated.trigger = isRealtime
            ? .realtime
            : .interval(IntervalSpec(unit: intervalUnit, count: intervalCount))
        let mode: RetentionPolicy.Mode
        switch retentionKind {
        case .automatic: mode = .automatic
        case .keepCount: mode = .keepCount(max(1, keepValue))
        case .keepDays: mode = .keepDays(max(1, keepValue))
        case .keepAll: mode = .keepAll
        }
        updated.retention = RetentionPolicy(
            mode: mode,
            minimumFreeBytes: Int64(max(0, minFreeGB) * Self.bytesPerGB),
            maxTotalBytes: Int64(max(0, quotaGB) * Self.bytesPerGB)
        )
        model.coordinator.updateJob(updated)
        dismiss()
    }
}
