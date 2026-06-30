//
//  @file        JobDetailView.swift
//  @description Detail dashboard for a job. Layout (option C): a source⟶destination visual header
//               (Carbon Copy Cloner style), a row of status/throughput stat cards plus storage and
//               quota gauges (Arq style), and a snapshot timeline (Time Machine style). Per-job
//               actions live in the sidebar row's ⋯ menu (not a toolbar here).
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-06-29
//  @lastUpdated 2026-06-30
//

import SwiftUI

struct JobDetailView: View {
    @Environment(AppModel.self) private var model
    let job: BackupJob
    @State private var plaintextCount = 0

    private var coordinator: BackupCoordinator { model.coordinator }
    private var state: JobRuntimeState { coordinator.state(for: job.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sourceDestinationHeader
                if state.isMigrating { migrationBanner }
                else if job.encryptionEnabled, plaintextCount > 0 { migrationPrompt }
                if let error = state.lastError { errorBanner(error) }
                statusCards
                storageSection
                snapshotsSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(job.name)
        .task(id: state.history.count) {
            plaintextCount = job.encryptionEnabled ? await coordinator.plaintextSnapshotCount(job.id) : 0
        }
    }

    // MARK: - Source → Destination header

    private var sourceDestinationHeader: some View {
        HStack(spacing: 14) {
            folderBadge(icon: "folder.fill",
                        name: job.sources.first?.lastPathComponent ?? "—",
                        path: job.sources.first?.path ?? "—",
                        tint: .secondary)
            VStack(spacing: 4) {
                Image(systemName: state.isRunning ? "arrow.right.circle.fill" : "arrow.right")
                    .font(.title)
                    .foregroundStyle(Color.wpDesignYellow)
                    .symbolEffect(.pulse, isActive: state.isRunning)
            }
            folderBadge(icon: "externaldrive.fill",
                        name: job.destination.lastPathComponent,
                        path: job.destination.path,
                        tint: .wpDesignYellow)
        }
    }

    private func folderBadge(icon: String, name: String, path: String, tint: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 30)).foregroundStyle(tint)
            Text(name).font(.callout.weight(.medium)).lineLimit(1)
            Text(path).font(.caption2).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .cardSurface()
    }

    // MARK: - Status cards

    private var statusCards: some View {
        HStack(spacing: 12) {
            if state.isRunning {
                StatCard(title: "Backing up", value: "\(byteString(Int64(state.throughputBytesPerSec)))/s",
                         systemImage: "arrow.up.circle.fill", tint: .wpDesignYellow)
                StatCard(title: "Files this pass", value: "\(state.progress.filesProcessed)",
                         systemImage: "doc.on.doc")
            } else {
                StatCard(title: "Last backup", value: lastBackupText,
                         systemImage: "checkmark.circle.fill", tint: .wpDesignYellow)
                StatCard(title: nextLabel, value: nextValue, systemImage: "calendar")
            }
            StatCard(title: "Snapshots", value: "\(state.history.count)",
                     systemImage: "square.stack.3d.up")
        }
    }

    // MARK: - Storage / quota

    @ViewBuilder
    private var storageSection: some View {
        VStack(spacing: 12) {
            if let free = state.destinationFreeBytes, let total = state.destinationTotalBytes, total > 0 {
                StorageGauge(label: "Destination · \(byteString(free)) free of \(byteString(total))",
                             usedFraction: Double(total - free) / Double(total))
            }
            if job.retention.maxTotalBytes > 0 {
                let used = state.history.reduce(Int64(0)) { $0 + $1.addedBlocks * 512 }
                StorageGauge(label: "Backup quota · \(byteString(used)) of \(byteString(job.retention.maxTotalBytes))",
                             usedFraction: Double(used) / Double(job.retention.maxTotalBytes))
            }
        }
    }

    // MARK: - Snapshot timeline

    @ViewBuilder
    private var snapshotsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Snapshots").font(.headline)
            if state.history.isEmpty {
                Text("No snapshots yet.").foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(state.history.enumerated()), id: \.element.id) { index, snap in
                        timelineRow(snap, isLast: index == state.history.count - 1)
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 14)
                .cardSurface()
            }
        }
    }

    private func timelineRow(_ snap: SnapshotRecord, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Circle().fill(color(for: snap.status)).frame(width: 9, height: 9).padding(.top, 5)
                if !isLast { Rectangle().fill(.quaternary).frame(width: 1.5).frame(maxHeight: .infinity) }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(snap.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.callout.weight(.medium))
                Text("\(snap.fileCount) files · \(byteString(snap.logicalBytes))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private var migrationPrompt: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.open.trianglebadge.exclamationmark")
                .font(.title3).foregroundStyle(Color.wpDesignYellow)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(plaintextCount) plaintext snapshot\(plaintextCount == 1 ? "" : "s") not yet encrypted")
                    .font(.callout.weight(.medium))
                Text("Convert them into the encrypted repo, then remove the plaintext copies.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Migrate Now") { coordinator.migrateToEncrypted(job.id) }
                .buttonStyle(.borderedProminent).tint(Color.wpDesignYellow).foregroundStyle(.black)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.wpDesignYellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var migrationBanner: some View {
        let text = state.migrationProgress.map { "Migrating to encrypted… \($0.done)/\($0.total)" }
            ?? "Migrating to encrypted…"
        return HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(text).font(.callout)
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.wpDesignYellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func errorBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(Color.wpRed)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.wpRed.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var lastBackupText: String {
        guard let last = state.lastSnapshot else { return "Never" }
        return last.timestamp.formatted(.relative(presentation: .named))
    }

    private var nextLabel: String {
        if case .interval = job.trigger { return "Next scheduled" }
        return "Trigger"
    }

    private var nextValue: String {
        switch job.trigger {
        case .realtime:
            return "Realtime"
        case .interval(let spec):
            if let next = Scheduler.nextDue(spec: spec, lastBackup: state.lastSnapshot?.timestamp) {
                return next.formatted(.relative(presentation: .named))
            }
            return "Every \(spec.count) \(spec.unit.rawValue)"
        }
    }

    private func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func color(for status: SnapshotStatus) -> Color {
        switch status {
        case .complete: return .wpDesignYellow
        case .failed: return .wpRed
        case .inProgress: return .secondary
        }
    }
}
