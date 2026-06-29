//
//  @file        SpectaBackupApp.swift
//  @description SwiftUI app entry point for SpectaBackup. Declares the dashboard Window and the
//               menu-bar dropdown (MenuBarExtra, .window style). The shared AppModel is created
//               here and injected into both scenes.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-06-29
//  @lastUpdated 2026-06-29
//
//  Notes:
//  - Scenes: a single `Window` (id "dashboard") plus a `MenuBarExtra`. Not WindowGroup — backup
//    config is a single document-less app surface, so one window is correct.
//  - AppModel is @MainActor @Observable (Swift 6 style); it owns the coordinator/metrics once
//    those services land. For now it is a thin placeholder so the app launches.
//

import SwiftUI

@main
struct SpectaBackupApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        // MARK: - Dashboard window (main surface)
        Window("SpectaBackup", id: AppModel.dashboardWindowID) {
            DashboardView()
                .environment(model)
        }
        .defaultSize(width: 980, height: 640)

        // MARK: - Menu-bar dropdown (status + quick controls)
        MenuBarExtra("SpectaBackup", systemImage: "externaldrive.fill") {
            MenuBarView()
                .environment(model)
        }
        .menuBarExtraStyle(.window)
    }
}
