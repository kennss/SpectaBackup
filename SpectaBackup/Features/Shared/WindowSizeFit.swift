//
//  @file        WindowSizeFit.swift
//  @description Keeps the dashboard window usable on launch. macOS restores a window's saved frame,
//               which can come back larger than the current screen (e.g. after a display change or a
//               stale restoration) and leave the title bar / resize edges off-screen. This caps the
//               window at the screen size and shrinks an oversized one to a comfortable centered size.
//               It never touches a window that already fits, so a size the user chose is preserved.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-07-01
//  @lastUpdated 2026-07-01
//
//  Notes:
//  - Frame restoration is applied by AppKit AFTER the view attaches, so a single clamp can be
//    overwritten. We re-check at several deadlines (and cap maxSize) to reliably win the race.
//

import SwiftUI
import AppKit

/// Attach with `.background(WindowSizeFit())`.
struct WindowSizeFit: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let probe = NSView()
        // Restoration timing varies; re-apply across the first ~1.5s to catch it whenever it lands.
        for delay in [0.0, 0.15, 0.4, 0.8, 1.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak probe] in
                fit(window: probe?.window)
            }
        }
        return probe
    }

    private func fit(window: NSWindow?) {
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        // Never allow the window to grow past the screen.
        window.maxSize = NSSize(width: visible.width, height: visible.height)
        let frame = window.frame
        // Only resize when it doesn't fit — otherwise leave the user's chosen size alone.
        guard frame.width > visible.width || frame.height > visible.height else { return }
        let width = min(1040, visible.width * 0.7)
        let height = min(760, visible.height * 0.85)
        let origin = CGPoint(x: visible.midX - width / 2, y: visible.midY - height / 2)
        window.setFrame(CGRect(origin: origin, size: CGSize(width: width, height: height)),
                        display: true, animate: false)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
