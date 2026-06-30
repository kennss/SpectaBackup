//
//  @file        WindowSizeFit.swift
//  @description Keeps the dashboard window usable on launch. macOS restores a window's saved frame,
//               which can come back larger than the current screen (e.g. after a display change or a
//               stale restoration) and leave the title bar / resize edges off-screen. This shrinks an
//               oversized window to a comfortable size, centered on the active screen. It never touches
//               a window that already fits, so a size the user deliberately chose is preserved.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-07-01
//  @lastUpdated 2026-07-01
//

import SwiftUI
import AppKit

/// Attach with `.background(WindowSizeFit())`. Runs once after the hosting window attaches.
struct WindowSizeFit: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let probe = NSView()
        DispatchQueue.main.async { [weak probe] in
            guard let window = probe?.window,
                  let screen = window.screen ?? NSScreen.main else { return }
            let visible = screen.visibleFrame
            let frame = window.frame
            // Only act when the window doesn't fit the screen — otherwise leave the user's size alone.
            guard frame.width > visible.width || frame.height > visible.height else { return }
            let width = min(1040, visible.width * 0.7)
            let height = min(760, visible.height * 0.85)
            let origin = CGPoint(x: visible.midX - width / 2, y: visible.midY - height / 2)
            window.setFrame(CGRect(origin: origin, size: CGSize(width: width, height: height)),
                            display: true, animate: false)
        }
        return probe
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
