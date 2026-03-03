import AppKit
import SwiftUI

/// Floating non-activating panel that shows transcription state.
/// Positioned at bottom-center of the main screen.
@MainActor
final class OverlayWindow {

    private var panel: NSPanel?
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Public

    func show() {
        if panel == nil { createPanel() }
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    // MARK: - Private

    private func createPanel() {
        let hostingView = NSHostingView(rootView: OverlayView(appState: appState))
        hostingView.frame = NSRect(x: 0, y: 0, width: 200, height: 40)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = true
        panel.contentView = hostingView

        positionPanel(panel)
        self.panel = panel
    }

    private func positionPanel(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - panel.frame.width / 2
        let y = screenFrame.minY + Constants.UI.overlayBottomOffset
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
