//
//  @file        DashboardView.swift
//  @description Dashboard window: a sidebar list of backup jobs plus a detail pane. Add a job by
//               picking a source folder and a destination; select a job to see status, run a manual
//               backup, and browse snapshot history. The empty state shows the wordmark and, when
//               Full Disk Access is missing, a branded onboarding card (auto-refreshed on focus).
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-06-29
//  @lastUpdated 2026-06-29
//

import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedJobID: UUID?
    @State private var fdaGranted = FullDiskAccess.isGranted

    private var coordinator: BackupCoordinator { model.coordinator }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedJobID) {
                ForEach(coordinator.jobs) { job in
                    JobRow(job: job, state: coordinator.state(for: job.id))
                        .tag(job.id)
                }
            }
            .navigationTitle("Backups")
            .frame(minWidth: 240)
            .toolbar {
                ToolbarItem {
                    Button(action: addJob) {
                        Label("Add Backup", systemImage: "plus")
                    }
                }
            }
        } detail: {
            if let id = selectedJobID, let job = coordinator.jobs.first(where: { $0.id == id }) {
                JobDetailView(job: job)
            } else {
                emptyState
            }
        }
        // Re-check FDA when the user returns from System Settings — no relaunch needed.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { fdaGranted = FullDiskAccess.isGranted }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 28) {
            Image("Wordmark")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 300)
            if fdaGranted {
                Text("Add a folder to back up with the + button.")
                    .foregroundStyle(.secondary)
            } else {
                fdaCard
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var fdaCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 34))
                .foregroundStyle(Color.wpDesignYellow)
            Text("Full Disk Access Needed")
                .font(.title3.bold())
            Text("SpectaBackup needs Full Disk Access to read protected folders like Desktop, Documents, and Downloads.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open System Settings…") { FullDiskAccess.openSystemSettings() }
                .buttonStyle(.borderedProminent)
                .tint(Color.wpDesignYellow)
                .foregroundStyle(.black)
                .controlSize(.large)
                .padding(.top, 4)
        }
        .padding(28)
        .frame(maxWidth: 380)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.wpDesignYellow.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 16, y: 6)
    }

    // MARK: - Actions

    private func addJob() {
        guard let source = FolderPicker.pick(prompt: "Choose Source",
                                             message: "Choose the folder to back up.") else { return }
        guard let destination = FolderPicker.pick(prompt: "Choose Destination",
                                                  message: "Choose where snapshots are stored (local disk or NAS).") else { return }
        let job = BackupJob(name: source.lastPathComponent, sources: [source], destination: destination)
        coordinator.addJob(job)
        selectedJobID = job.id
    }
}

/// Sidebar row: job name, destination, and a status dot.
private struct JobRow: View {
    let job: BackupJob
    let state: JobRuntimeState

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(state.isRunning ? Color.wpDesignYellow : Color.secondary.opacity(0.4))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(job.name).font(.body)
                Text(job.destination.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 2)
    }
}
