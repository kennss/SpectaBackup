//
//  @file        WindowSizeFit.swift
//  @description Keeps the dashboard window from opening larger than the screen. SwiftUI's `Window`
//               scene restores a persisted frame that can be bigger than the current display (leaving
//               the title bar / resize edges off-screen). `maxSize` alone doesn't help — it only limits
//               live user resizing, not the programmatic setFrame SwiftUI uses to restore. So we turn
//               off frame restoration AND observe the window: any time it ends up larger than the
//               screen (e.g. a late restoration), we shrink it to a comfortable centered size. A window
//               that already fits is never touched, so a size the user chose in-session is preserved.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-07-01
//  @lastUpdated 2026-07-01
//

import SwiftUI
import AppKit

/// Attach with `.background(WindowSizeFit())`.
struct WindowSizeFit: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { context.coordinator.attach(to: view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.attach(to: nsView.window)
    }

    final class Coordinator {
        private weak var window: NSWindow?
        private var observers: [NSObjectProtocol] = []

        func attach(to window: NSWindow?) {
            guard let window else { return }
            if window === self.window { fit(); return }
            self.window = window
            window.isRestorable = false                    // stop restoring a stale (oversized) frame
            let nc = NotificationCenter.default
            observers.forEach { nc.removeObserver($0) }
            // Re-fit whenever the window resizes/moves/activates — catches a late restoration setFrame.
            observers = [NSWindow.didResizeNotification,
                         NSWindow.didMoveNotification,
                         NSWindow.didBecomeMainNotification].map { name in
                nc.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in self?.fit() }
            }
            fit()
        }

        private func fit() {
            guard let window, let screen = window.screen ?? NSScreen.main else { return }
            let visible = screen.visibleFrame
            let frame = window.frame
            guard frame.width > visible.width || frame.height > visible.height else { return }
            let width = min(1040, visible.width * 0.7)
            let height = min(760, visible.height * 0.85)
            let origin = CGPoint(x: visible.midX - width / 2, y: visible.midY - height / 2)
            window.setFrame(CGRect(origin: origin, size: CGSize(width: width, height: height)),
                            display: true, animate: false)
        }

        deinit {
            observers.forEach { NotificationCenter.default.removeObserver($0) }
        }
    }
}
