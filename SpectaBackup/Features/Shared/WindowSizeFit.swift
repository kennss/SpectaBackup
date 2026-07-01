//
//  @file        WindowSizeFit.swift
//  @description Forces the dashboard window to a deterministic, screen-fitted launch size and stops
//               macOS from persisting/restoring an out-of-bounds frame. SwiftUI wires the `Window(id:)`
//               value as the NSWindow *frame autosave name*, so the frame is stored in UserDefaults
//               ("NSWindow Frame <id>") and, on the next launch, AppKit re-applies that saved frame —
//               overriding `.defaultSize` and any plain `setFrame`. This runs once on first window
//               attach: it severs the autosave association, purges the stored frame, then sets a
//               centered frame that fits the active display. It never touches the window again, so the
//               user can resize freely during the session (the size just isn't remembered across launches).
//  @author      Kennt Kim
//  @company     Calida Lab
//  @created     2026-07-01
//  @lastUpdated 2026-07-01
//
//  Notes:
//  - All window mutation is deferred to a later main-actor turn. setFrame inside AppKit's constraint
//    pass throws (_postWindowNeedsUpdateConstraints) and crashes on launch.
//  - Order matters: clear the autosave name BEFORE setFrame so no later autosave restore can clobber it.
//    `isRestorable` governs Cocoa state restoration, NOT frame autosave — the real fix is setFrameAutosaveName("").
//  - `base` must stay in sync with `.defaultSize(...)` on the Window scene.
//

import SwiftUI
import AppKit

/// Attach with `.background(WindowSizeFit())` on the dashboard's root view.
struct WindowSizeFit: NSViewRepresentable {
    /// Preferred launch size; clamped to the active screen's visible frame. Keep in sync with `.defaultSize`.
    var base = CGSize(width: 980, height: 640)

    func makeCoordinator() -> Coordinator { Coordinator(base: base) }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let coordinator = context.coordinator
        // The view has no window during make; grab it on the next main-actor turn.
        Task { @MainActor in coordinator.configureOnce(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.configureOnce(nsView.window)
    }

    @MainActor
    final class Coordinator {
        private let base: CGSize
        private var done = false

        init(base: CGSize) { self.base = base }

        /// Runs exactly once, the first time a real window is available.
        func configureOnce(_ window: NSWindow?) {
            guard !done, let window else { return }   // stay un-done until a window actually exists
            done = true
            // Defer: never mutate the window frame inside the current constraint pass (past crash).
            Task { @MainActor [weak self, weak window] in
                guard let self, let window else { return }
                self.enforce(on: window)
            }
        }

        private func enforce(on window: NSWindow) {
            // 1) Break the frame-autosave association → AppKit stops restoring/saving this frame.
            window.setFrameAutosaveName("")
            // 2) Purge any already-persisted (stale, oversized) frame for this scene id.
            NSWindow.removeFrame(usingName: AppModel.dashboardWindowID)
            // 3) Belt-and-suspenders: keep this window out of Cocoa state restoration too.
            window.isRestorable = false
            // 4) Deterministic, centered frame that fits the ACTIVE display (multi-display safe).
            guard let screen = window.screen ?? NSScreen.main else { return }
            let visible = screen.visibleFrame
            let size = CGSize(width:  min(base.width,  visible.width  - 40),
                              height: min(base.height, visible.height - 40))
            let origin = CGPoint(x: visible.midX - size.width  / 2,
                                 y: visible.midY - size.height / 2)
            window.setFrame(CGRect(origin: origin, size: size), display: true, animate: false)
        }
    }
}
