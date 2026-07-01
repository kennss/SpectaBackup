//
//  @file        WindowSizeFit.swift
//  @description Keeps the dashboard window from opening larger than the screen. SwiftUI's `Window`
//               scene restores a persisted frame that can be bigger than the current display (leaving
//               the title bar / resize edges off-screen). We turn off frame restoration and, whenever
//               the window ends up larger than the screen, shrink it to a comfortable centered size.
//               A window that already fits is never touched, so an in-session size the user chose is
//               preserved.
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-07-01
//  @lastUpdated 2026-07-01
//
//  Notes:
//  - The resize MUST be deferred out of the current run-loop turn. Calling setFrame synchronously from
//    a window notification (didResize/…) lands inside AppKit's constraint-update cycle and throws
//    (_postWindowNeedsUpdateConstraints), crashing the app. We coalesce and hop to a later main-actor
//    turn (Task) instead.
//

import SwiftUI
import AppKit

/// Attach with `.background(WindowSizeFit())`.
struct WindowSizeFit: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let coordinator = context.coordinator
        Task { @MainActor in coordinator.attach(to: view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.attach(to: nsView.window)
    }

    @MainActor
    final class Coordinator {
        private weak var window: NSWindow?
        private var tokens: [NSObjectProtocol] = []
        private var pending = false

        func attach(to window: NSWindow?) {
            guard let window else { return }
            if window !== self.window {
                self.window = window
                window.isRestorable = false                 // don't restore a stale (oversized) frame
                let nc = NotificationCenter.default
                tokens.forEach { nc.removeObserver($0) }
                tokens = [NSWindow.didResizeNotification,
                          NSWindow.didMoveNotification,
                          NSWindow.didBecomeMainNotification].map { name in
                    nc.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated { self?.scheduleFit() }
                    }
                }
            }
            scheduleFit()
        }

        /// Coalesce and defer: never resize inside the current layout/constraint pass (that throws).
        private func scheduleFit() {
            guard !pending else { return }
            pending = true
            Task { @MainActor [weak self] in
                self?.pending = false
                self?.fit()
            }
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
    }
}
