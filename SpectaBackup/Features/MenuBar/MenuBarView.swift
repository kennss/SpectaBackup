//
//  @file        MenuBarView.swift
//  @description Menu-bar dropdown: overall status, a card per job (live throughput / last backup +
//               a destination free-space mini gauge), and quick actions. Matches the dashboard's
//               card design language.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-06-29
//  @lastUpdated 2026-06-29
//

import SwiftUI

struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    private var coordinator: BackupCoordinator { model.coordinator }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if coordinator.jobs.isEmpty {
                Text("No backups configured.")
                    .font(.callout).foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 8) {
                    ForEach(coordinator.jobs) { jobCard($0) }
                }
            }

            Divider()
            VStack(spacing: 2) {
                menuButton("Open Dashboard…", icon: "macwindow") { openWindow(id: AppModel.dashboardWindowID) }
                menuButton("Quit SpectaBackup", icon: "power") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 320)
        .onAppear { coordinator.refreshMetrics() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(coordinator.anyRunning ? Color.wpDesignYellow : Color.green)
                .frame(width: 8, height: 8)
            Text(coordinator.anyRunning ? "Backing up…" : "SpectaBackup")
                .font(.headline)
            Spacer()
        }
    }

    private func jobCard(_ job: BackupJob) -> some View {
        let state = coordinator.state(for: job.id)
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(job.name).font(.body.weight(.medium))
                Spacer()
                Button("Back Up") { coordinator.runNow(job.id) }
                    .controlSize(.small)
                    .disabled(state.isRunning)
            }
            if state.isRunning {
                Text("↑ \(byteString(Int64(state.throughputBytesPerSec)))/s · \(state.progress.filesProcessed) files")
                    .font(.caption).foregroundStyle(Color.wpDesignYellow)
            } else if let last = state.lastSnapshot {
                Text("Last backup \(last.timestamp.formatted(.relative(presentation: .named)))")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Never backed up").font(.caption).foregroundStyle(.secondary)
            }
            if let free = state.destinationFreeBytes, let total = state.destinationTotalBytes, total > 0 {
                storageMini(free: free, total: total)
            }
        }
        .padding(10)
        .cardSurface()
    }

    private func storageMini(free: Int64, total: Int64) -> some View {
        let used = 1 - Double(free) / Double(total)
        return VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "externaldrive.fill").font(.caption2)
                Text("\(byteString(free)) free").font(.caption2)
                Spacer()
                Text("\(Int((used * 100).rounded()))% used").font(.caption2)
            }
            .foregroundStyle(.secondary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(Color.wpDesignYellow)
                        .frame(width: max(0, min(1, used)) * geo.size.width)
                }
            }
            .frame(height: 4)
        }
    }

    private func menuButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).frame(width: 16)
                Text(title)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
    }

    private func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
