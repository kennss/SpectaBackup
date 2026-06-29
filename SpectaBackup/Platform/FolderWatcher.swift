//
//  @file        FolderWatcher.swift
//  @description FSEvents wrapper that watches a set of source paths and fires a coalesced callback on
//               any change. The engine always does a full stat-diff per pass, so we treat every event
//               (including the kernel's MustScanSubDirs/Dropped coalescing) uniformly as "something
//               changed — run a pass"; correctness comes from the diff, not from event granularity.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-06-29
//  @lastUpdated 2026-06-29
//
//  Notes:
//  - File-level events + IgnoreSelf; the destination lives outside the watched source roots, so our
//    own writes don't create an event storm.
//  - Stream runs on a private dispatch queue. The owner (BackupCoordinator) debounces the callback
//    and hops to the main actor before triggering a pass.
//

import CoreServices
import Foundation

final class FolderWatcher: @unchecked Sendable {

    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "ai.calidalab.spectabackup.watcher")
    private let paths: [String]
    private let latency: CFTimeInterval
    private let onChange: @Sendable () -> Void

    init(paths: [String], latency: TimeInterval = 1.0, onChange: @escaping @Sendable () -> Void) {
        self.paths = paths
        self.latency = latency
        self.onChange = onChange
    }

    func start() {
        guard stream == nil, !paths.isEmpty else { return }
        var context = FSEventStreamContext(version: 0,
                                           info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents
                           | kFSEventStreamCreateFlagUseCFTypes
                           | kFSEventStreamCreateFlagIgnoreSelf
                           | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(kCFAllocatorDefault,
                                               Self.eventCallback,
                                               &context,
                                               paths as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                                               latency,
                                               flags) else { return }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit { stop() }

    private static let eventCallback: FSEventStreamCallback = { _, info, _, _, _, _ in
        guard let info else { return }
        let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
        watcher.onChange()
    }
}
