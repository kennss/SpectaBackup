//
//  @file        BackupCoordinator.swift
//  @description Main-actor, observable owner of the job list and per-job runtime state. Persists job
//               config, kicks off passes on the BackupRunner actor, and marshals progress/results
//               back to the UI. The single source of truth the dashboard and menu bar both observe.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-06-29
//  @lastUpdated 2026-06-29
//
//  Notes:
//  - @Observable + @MainActor (Swift 6). UI reads `jobs` and `state(for:)`; heavy work is on `runner`.
//  - A job won't start a second pass while one is running (per-job `isRunning` guard); the runner
//    actor additionally serializes execution to avoid concurrent destination writes.
//

import Foundation

@MainActor
@Observable
final class BackupCoordinator {

    private(set) var jobs: [BackupJob]
    private(set) var states: [UUID: JobRuntimeState] = [:]

    private let store = JobStore()
    private let runner = BackupRunner()
    private var watchers: [UUID: FolderWatcher] = [:]
    private var debounceTasks: [UUID: Task<Void, Never>] = [:]
    private var meters: [UUID: ThroughputMeter] = [:]
    private var scheduleTicker: Task<Void, Never>?

    init() {
        jobs = store.load()
    }

    // MARK: - Accessors

    func state(for id: UUID) -> JobRuntimeState {
        states[id] ?? JobRuntimeState()
    }

    var anyRunning: Bool {
        states.values.contains { $0.isRunning }
    }

    // MARK: - Job management

    func addJob(_ job: BackupJob) {
        jobs.append(job)
        persist()
        loadHistory(for: job)
        if case .realtime = job.trigger { startWatcher(for: job) }
        // Immediate first backup of the (possibly already-populated) folder — requirement #4.
        runNow(job.id)
    }

    func removeJob(_ id: UUID, deleteSnapshots: Bool = false) {
        stopWatcher(id)
        let job = jobs.first(where: { $0.id == id })
        jobs.removeAll { $0.id == id }
        states[id] = nil
        persist()
        if deleteSnapshots, let job {
            KeychainStorage.removePassword(for: id)   // drop the encrypted repo's key too, if any
            Task { await runner.deleteJobData(for: job) }
        }
    }

    /// Apply edited settings (trigger / retention / quota) and restart its watcher accordingly.
    /// Interval jobs are picked up by the schedule ticker, which reads `jobs` live.
    func updateJob(_ job: BackupJob) {
        guard let idx = jobs.firstIndex(where: { $0.id == job.id }) else { return }
        jobs[idx] = job
        persist()
        stopWatcher(job.id)
        if job.isEnabled, case .realtime = job.trigger { startWatcher(for: job) }
    }

    /// Initialize (or verify) an encrypted job's repo and store its password in the Keychain. Returns
    /// the recovery key when the repo was just created (show it ONCE), or nil if it already existed.
    /// The heavy argon2 KDF / repo creation runs off the main actor.
    func enableEncryption(for job: BackupJob, password: String) async throws -> String? {
        let repoRoot = BackupRunner.jobRoot(for: job).appendingPathComponent("repo", isDirectory: true)
        let pw = Data(password.utf8)
        let recovery = try await Task.detached(priority: .userInitiated) { () -> String? in
            let backend = try LocalBackend(root: repoRoot)
            if await RepoManager.isInitialized(backend) {
                _ = try await RepoManager.unlock(backend: backend, password: pw)   // verify password
                return nil
            }
            return try await RepoManager.create(backend: backend, password: pw).recoveryKey
        }.value
        KeychainStorage.setPassword(password, for: job.id)
        return recovery
    }

    private func persist() {
        try? store.save(jobs)
    }

    // MARK: - Running

    func runNow(_ jobID: UUID, quietWindow: TimeInterval = 0) {
        guard let job = jobs.first(where: { $0.id == jobID }) else { return }
        let current = state(for: jobID)
        guard !current.isRunning, !current.isMigrating else { return }
        var st = state(for: jobID)
        st.isRunning = true
        st.lastError = nil
        st.progress = BackupProgress()
        states[jobID] = st

        Task { await execute(job: job, quietWindow: quietWindow) }
    }

    private func execute(job: BackupJob, quietWindow: TimeInterval) async {
        let jobID = job.id
        meters[jobID] = ThroughputMeter()
        updateFreeSpace(jobID)
        let progress: @Sendable (BackupProgress) -> Void = { p in
            Task { @MainActor [weak self] in self?.applyProgress(p, for: jobID) }
        }
        do {
            let result = try await runner.run(job: job, quietWindow: quietWindow, progress: progress)
            let history = (try? await runner.history(for: job)) ?? []
            var st = state(for: jobID)
            st.isRunning = false
            st.throughputBytesPerSec = 0
            if let snap = result.snapshot { st.lastSnapshot = snap }
            st.history = history
            states[jobID] = st
            updateFreeSpace(jobID)
        } catch {
            var st = state(for: jobID)
            st.isRunning = false
            st.throughputBytesPerSec = 0
            st.lastError = String(describing: error)
            states[jobID] = st
        }
    }

    private func applyProgress(_ p: BackupProgress, for jobID: UUID) {
        var meter = meters[jobID] ?? ThroughputMeter()
        meter.update(totalBytes: p.bytesCopied, now: Date())
        meters[jobID] = meter
        guard var st = states[jobID] else { return }
        st.progress = p
        st.throughputBytesPerSec = meter.bytesPerSecond
        states[jobID] = st
    }

    private func updateFreeSpace(_ jobID: UUID) {
        guard let job = jobs.first(where: { $0.id == jobID }) else { return }
        let info = try? Syscalls.volumeInfo(at: job.destination.path)
        var st = state(for: jobID)
        st.destinationFreeBytes = info?.freeBytes
        st.destinationTotalBytes = info?.totalBytes
        states[jobID] = st
    }

    // MARK: - History

    /// Load snapshot history for all jobs (call at launch).
    func refreshAllHistory() {
        for job in jobs { loadHistory(for: job) }
    }

    /// Refresh destination free space for all jobs (e.g. when the menu bar opens).
    func refreshMetrics() {
        for job in jobs { updateFreeSpace(job.id) }
    }

    /// Free/total space per destination VOLUME, aggregated across jobs that target the same disk.
    /// Volumes that aren't mounted (e.g. a disconnected NAS) are skipped.
    func destinationUsages() -> [DestinationUsage] {
        let keys: Set<URLResourceKey> = [.volumeURLKey, .volumeNameKey,
                                         .volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        var byVolume: [String: DestinationUsage] = [:]
        for job in jobs {
            guard let rv = try? job.destination.resourceValues(forKeys: keys),
                  let volumeURL = rv.volume else { continue }
            let mount = volumeURL.path
            if byVolume[mount] != nil {
                byVolume[mount]?.jobCount += 1
            } else {
                byVolume[mount] = DestinationUsage(
                    id: mount,
                    name: rv.volumeName ?? volumeURL.lastPathComponent,
                    freeBytes: Int64(rv.volumeAvailableCapacityForImportantUsage ?? 0),
                    totalBytes: Int64(rv.volumeTotalCapacity ?? 0),
                    jobCount: 1)
            }
        }
        return byVolume.values.sorted { $0.name < $1.name }
    }

    private func loadHistory(for job: BackupJob) {
        let jobID = job.id
        Task {
            let history = (try? await runner.history(for: job)) ?? []
            var st = state(for: jobID)
            st.history = history
            st.lastSnapshot = history.first { $0.status == .complete }
            states[jobID] = st
        }
    }

    // MARK: - Restore

    /// Source-root URL inside a snapshot, for browsing in the restore UI.
    func snapshotSourceRoot(jobID: UUID, snapshotDirName: String, sourceName: String) -> URL? {
        guard let job = jobs.first(where: { $0.id == jobID }) else { return nil }
        return BackupRunner.jobRoot(for: job)
            .appendingPathComponent("snapshots/\(snapshotDirName)/\(sourceName)", isDirectory: true)
    }

    /// Restore selected items from a snapshot into a target directory (runs off the main actor).
    func restore(jobID: UUID, snapshotDirName: String, sourceName: String,
                 relPaths: [String], to target: URL, conflict: RestoreEngine.ConflictPolicy,
                 progress: @escaping @Sendable (Int) -> Void) async throws -> RestoreEngine.Outcome {
        guard let job = jobs.first(where: { $0.id == jobID }) else { return RestoreEngine.Outcome() }
        return try await runner.restore(job: job, snapshotDirName: snapshotDirName, sourceName: sourceName,
                                        relPaths: relPaths, to: target, conflict: conflict, progress: progress)
    }

    /// Restore an entire encrypted snapshot into a target folder.
    func restoreEncrypted(jobID: UUID, snapshotDirName: String, to target: URL) async throws {
        guard let job = jobs.first(where: { $0.id == jobID }) else { return }
        try await runner.restoreEncrypted(job: job, snapshotID: snapshotDirName, to: target)
    }

    // MARK: - Encryption migration

    /// How many plaintext snapshots a job still has (used to decide whether to migrate).
    func plaintextSnapshotCount(_ jobID: UUID) async -> Int {
        guard let job = jobs.first(where: { $0.id == jobID }) else { return 0 }
        return await runner.plaintextSnapshotCount(for: job)
    }

    /// Migrate a job's plaintext snapshots into its encrypted repo (off-main), surfacing progress and
    /// keeping the plaintext intact if anything fails.
    func migrateToEncrypted(_ jobID: UUID) {
        guard let job = jobs.first(where: { $0.id == jobID }) else { return }
        var st = state(for: jobID)
        st.isMigrating = true
        st.migrationProgress = MigrationProgress(done: 0, total: 0)
        st.lastError = nil
        states[jobID] = st

        let progress: @Sendable (Int, Int) -> Void = { done, total in
            Task { @MainActor [weak self] in
                guard var s = self?.states[jobID] else { return }
                s.migrationProgress = MigrationProgress(done: done, total: total)
                self?.states[jobID] = s
            }
        }
        Task {
            do {
                try await runner.migrateToEncrypted(job: job, progress: progress)
                loadHistory(for: job)
            } catch {
                var s = state(for: jobID)
                s.lastError = "Migration failed — plaintext backups kept: \(error)"
                states[jobID] = s
            }
            var s = state(for: jobID)
            s.isMigrating = false
            s.migrationProgress = nil
            states[jobID] = s
            updateFreeSpace(jobID)
        }
    }

    // MARK: - Realtime monitoring

    /// Start FSEvents watchers for all enabled realtime jobs (call at launch).
    func startMonitoring() {
        for job in jobs where job.isEnabled {
            if case .realtime = job.trigger { startWatcher(for: job) }
        }
        startScheduleTicker()
    }

    /// Periodically fire interval-triggered jobs that have come due (also catches missed runs).
    private func startScheduleTicker() {
        scheduleTicker?.cancel()
        scheduleTicker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                if Task.isCancelled { break }
                self?.checkSchedules()
            }
        }
    }

    private func checkSchedules() {
        let now = Date()
        for job in jobs where job.isEnabled {
            guard case .interval(let spec) = job.trigger else { continue }
            let last = state(for: job.id).lastSnapshot?.timestamp
            if Scheduler.isDue(spec: spec, lastBackup: last, now: now) {
                runNow(job.id)
            }
        }
    }

    private func startWatcher(for job: BackupJob) {
        let jobID = job.id
        let watcher = FolderWatcher(paths: job.sources.map(\.path)) { [weak self] in
            Task { @MainActor in self?.handleChange(jobID) }
        }
        watcher.start()
        watchers[jobID] = watcher
    }

    private func stopWatcher(_ id: UUID) {
        watchers[id]?.stop()
        watchers[id] = nil
        debounceTasks[id]?.cancel()
        debounceTasks[id] = nil
    }

    /// Debounce filesystem events: run a pass once changes go quiet for ~2s.
    private func handleChange(_ jobID: UUID) {
        debounceTasks[jobID]?.cancel()
        debounceTasks[jobID] = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self.runNow(jobID, quietWindow: 3)
        }
    }
}
