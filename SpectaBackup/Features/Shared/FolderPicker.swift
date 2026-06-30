//
//  @file        FolderPicker.swift
//  @description Small AppKit helper to choose a folder via NSOpenPanel. The app is non-sandboxed, so
//               the returned URL can be used directly (no security-scoped bookmark needed). The panel
//               opens at `defaultDirectory` (home by default) instead of the OS-remembered location.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-06-29
//  @lastUpdated 2026-06-30
//

import AppKit

enum FolderPicker {
    /// Present a folder picker. `defaultDirectory` is the folder shown when the panel opens; pass nil
    /// to let macOS restore its last-used location.
    @MainActor
    static func pick(prompt: String, message: String,
                     defaultDirectory: URL? = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = prompt
        panel.message = message
        panel.directoryURL = defaultDirectory
        return panel.runModal() == .OK ? panel.url : nil
    }
}
