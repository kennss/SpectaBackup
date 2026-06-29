//
//  @file        AppModel.swift
//  @description Root app model for SpectaBackup. Owns shared, observable app state and (later) the
//               BackupCoordinator and Metrics services. Injected into all scenes via @Environment.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-06-29
//  @lastUpdated 2026-06-29
//
//  Notes:
//  - @MainActor @Observable singleton-style model (Swift 6). Services are added in later tasks;
//    `dashboardWindowID` is the stable id used by openWindow(id:) from the menu bar.
//

import Foundation

@MainActor
@Observable
final class AppModel {
    /// Stable identifier for the dashboard `Window` scene; used by `openWindow(id:)`.
    static let dashboardWindowID = "dashboard"

    /// Owner of the job list and per-job runtime state, observed by the dashboard and menu bar.
    let coordinator = BackupCoordinator()

    init() {
        coordinator.refreshAllHistory()
        coordinator.startMonitoring()
    }
}
