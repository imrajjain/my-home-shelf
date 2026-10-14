import AppKit
import SwiftUI
import ShelfCore

/// A borderless floating panel that can take keyboard focus without
/// activating Shelf — your browser stays frontmost, like Spotlight.
final class CapturePanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 460),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class QuickCaptureController: NSObject, NSWindowDelegate {
    static let shared = QuickCaptureController()

    private var panel: CapturePanel?
    var isVisible: Bool { panel?.isVisible == true }

    func toggle() {
        isVisible ? close() : show(prefill: nil)
    }

    func show(prefill: CaptureRequest?) {
        // Who was in front before us? (Used to read the current browser tab.)
        let front = NSWorkspace.shared.frontmostApplication
        let frontmost = front?.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : front

        let panel = self.panel ?? makePanel()
        self.panel = panel

        // Fresh view each time so state never leaks between captures.
        let root = CaptureView(presentation: .panel, prefill: prefill, frontmostApp: frontmost) { [weak self] in
            self?.close()
        }
        .modelContainer(Persistence.container)
        .tint(Color.accent)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(x: 0, y: 0, width: 640, height: 460)
        panel.contentView = hosting

        position(panel)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            panel.animator().alphaValue = 1
        }
        panel.invalidateShadow()
    }

    func close() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in
                panel.orderOut(nil)
                panel.contentView = nil
            }
        })
    }

    private func makePanel() -> CapturePanel {
        let panel = CapturePanel()
        panel.delegate = self
        return panel
    }

    /// Centered horizontally, a little above middle, on the screen with the mouse.
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { panel.center(); return }
        let size = panel.frame.size
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.minY + visible.height * 0.62 - size.height / 2
        )
        panel.setFrameOrigin(origin)
    }

    // Clicking anywhere else dismisses, like a popover.
    nonisolated func windowDidResignKey(_ notification: Notification) {
        Task { @MainActor in self.close() }
    }
}
