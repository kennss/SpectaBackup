//
//  @file        RestoreView.swift
//  @description Restore sheet: pick a snapshot (and source, if several), browse/select files in a
//               custom lazy tree (compact rows, circular checks, indentation, hover/selection
//               highlight), choose a target and conflict policy, then restore. Ownership can't be
//               restored (non-root) — noted in the footer.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-06-29
//  @lastUpdated 2026-06-29
//

import SwiftUI

struct RestoreView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let job: BackupJob
    let history: [SnapshotRecord]

    @State private var snapshot: SnapshotRecord?
    @State private var sourceName: String
    @State private var selection = Set<String>()
    @State private var useOriginalLocation = true
    @State private var customTarget: URL?
    @State private var conflict: RestoreEngine.ConflictPolicy = .keepBoth
    @State private var isRestoring = false
    @State private var resultMessage: String?

    init(job: BackupJob, history: [SnapshotRecord]) {
        self.job = job
        self.history = history
        _snapshot = State(initialValue: history.first { $0.status == .complete })
        _sourceName = State(initialValue: job.sources.first?.lastPathComponent ?? "")
    }

    private var completeSnapshots: [SnapshotRecord] { history.filter { $0.status == .complete } }

    private var browser: SnapshotBrowser? {
        guard let snapshot,
              let root = model.coordinator.snapshotSourceRoot(jobID: job.id,
                                                              snapshotDirName: snapshot.dirName,
                                                              sourceName: sourceName)
        else { return nil }
        return SnapshotBrowser(sourceRoot: root)
    }

    private var resolvedTarget: URL? {
        useOriginalLocation ? job.sources.first { $0.lastPathComponent == sourceName } : customTarget
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            pickerBar
            Divider()
            treeSection
            Divider()
            footer
        }
        .frame(width: 700, height: 600)
        .onChange(of: snapshot) { _, _ in selection.removeAll() }
        .onChange(of: sourceName) { _, _ in selection.removeAll() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath").foregroundStyle(Color.wpDesignYellow)
            Text("Restore").font(.headline)
            Spacer()
            if !selection.isEmpty {
                Button("Clear") { selection.removeAll() }.controlSize(.small)
            }
            Button("Close") { dismiss() }
        }
        .padding(16)
    }

    // MARK: - Snapshot / source pickers

    private var pickerBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                Text("Snapshot").foregroundStyle(.secondary)
                Picker("", selection: $snapshot) {
                    ForEach(completeSnapshots) { snap in
                        Text("\(snap.timestamp.formatted(date: .abbreviated, time: .shortened)) · \(snap.fileCount) files")
                            .tag(snap as SnapshotRecord?)
                    }
                }
                .labelsHidden()
            }
            if job.sources.count > 1 {
                HStack(spacing: 8) {
                    Text("Source").foregroundStyle(.secondary)
                    Picker("", selection: $sourceName) {
                        ForEach(job.sources, id: \.self) { Text($0.lastPathComponent).tag($0.lastPathComponent) }
                    }
                    .labelsHidden().frame(width: 160)
                }
            }
            Spacer()
            if !selection.isEmpty {
                Text("\(selection.count) selected").font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - File tree

    @ViewBuilder
    private var treeSection: some View {
        if let browser {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(browser.children(of: "")) { entry in
                        SnapshotTreeRow(entry: entry, depth: 0, browser: browser, selection: $selection)
                    }
                }
                .padding(8)
            }
        } else {
            ContentUnavailableView("No snapshot", systemImage: "clock.badge.questionmark")
                .frame(maxHeight: .infinity)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("Restore to").foregroundStyle(.secondary)
                Picker("", selection: $useOriginalLocation) {
                    Text("Original location").tag(true)
                    Text("Another folder").tag(false)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 280)
                if !useOriginalLocation {
                    Button(customTarget?.lastPathComponent ?? "Choose…") {
                        customTarget = FolderPicker.pick(prompt: "Choose Restore Target",
                                                         message: "Restore selected items into this folder.")
                    }
                }
                Spacer()
            }

            HStack(spacing: 10) {
                Text("If a file exists").foregroundStyle(.secondary)
                Picker("", selection: $conflict) {
                    ForEach(RestoreEngine.ConflictPolicy.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden().frame(width: 160)
                Spacer()
            }

            HStack {
                Text("Ownership isn't restored — files will be owned by you.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let resultMessage {
                    Text(resultMessage).font(.callout).foregroundStyle(.secondary)
                }
                if isRestoring { ProgressView().controlSize(.small) }
                Button("Restore \(selection.count) item\(selection.count == 1 ? "" : "s")") { performRestore() }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.wpDesignYellow)
                    .foregroundStyle(.black)
                    .disabled(selection.isEmpty || resolvedTarget == nil || isRestoring || snapshot == nil)
            }
        }
        .padding(16)
    }

    // MARK: - Action

    private func performRestore() {
        guard let snapshot, let target = resolvedTarget else { return }
        isRestoring = true
        resultMessage = nil
        let rels = Array(selection)
        let conflictPolicy = conflict
        let src = sourceName
        Task {
            do {
                let outcome = try await model.coordinator.restore(
                    jobID: job.id, snapshotDirName: snapshot.dirName, sourceName: src,
                    relPaths: rels, to: target, conflict: conflictPolicy, progress: { _ in })
                isRestoring = false
                var msg = "Restored \(outcome.restored)"
                if outcome.skipped > 0 { msg += ", skipped \(outcome.skipped)" }
                if !outcome.failed.isEmpty { msg += ", failed \(outcome.failed.count)" }
                resultMessage = msg
            } catch {
                isRestoring = false
                resultMessage = "Failed: \(error)"
            }
        }
    }
}

/// One row in the snapshot file tree. Custom (not List) for a compact, modern look: indentation by
/// depth, an animated chevron for directories, a circular check, and hover/selection highlight.
private struct SnapshotTreeRow: View {
    let entry: SnapshotEntry
    let depth: Int
    let browser: SnapshotBrowser
    @Binding var selection: Set<String>

    @State private var expanded = false
    @State private var children: [SnapshotEntry]?
    @State private var hovering = false

    private var isSelected: Bool { selection.contains(entry.relPath) }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            rowContent
            if expanded {
                ForEach(children ?? []) { child in
                    SnapshotTreeRow(entry: child, depth: depth + 1, browser: browser, selection: $selection)
                }
            }
        }
    }

    private var rowContent: some View {
        HStack(spacing: 7) {
            Group {
                if entry.isDirectory {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                } else {
                    Color.clear
                }
            }
            .frame(width: 12)

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.wpDesignYellow : Color.secondary.opacity(0.4))
                .font(.body)
                .contentShape(Rectangle())
                .onTapGesture { toggleSelect() }

            Image(systemName: entry.isDirectory ? "folder.fill" : "doc")
                .foregroundStyle(entry.isDirectory ? Color.wpDesignYellow : .secondary)
                .frame(width: 16)

            Text(entry.name).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .padding(.leading, CGFloat(depth) * 16 + 8)
        .padding(.trailing, 8)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color.wpDesignYellow.opacity(0.14)
                                 : (hovering ? Color.primary.opacity(0.06) : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture { entry.isDirectory ? toggleExpand() : toggleSelect() }
        .onHover { hovering = $0 }
    }

    private func toggleExpand() {
        if children == nil { children = browser.children(of: entry.relPath) }
        withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
    }

    private func toggleSelect() {
        if isSelected { selection.remove(entry.relPath) } else { selection.insert(entry.relPath) }
    }
}
