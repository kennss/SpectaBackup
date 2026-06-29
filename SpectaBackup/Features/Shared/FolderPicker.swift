//
//  @file        FolderPicker.swift
//  @description Small AppKit helper to choose a folder via NSOpenPanel. The app is non-sandboxed, so
//               the returned URL can be used directly (no security-scoped bookmark needed).
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-06-29
//  @lastUpdated 2026-06-29
//

import AppKit

enum FolderPicker {
    @MainActor
    static func pick(prompt: String, message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = prompt
        panel.message = message
        return panel.runModal() == .OK ? panel.url : nil
    }
}
