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
        guard appState.showOverlay else { return }
        if panel == nil { createPanel() }
        positionPanel(panel!)
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
        let panelWidth = panel.frame.width
        let panelHeight = panel.frame.height

        let origin: NSPoint
        switch appState.overlayPosition {
        case .bottomCenter:
            origin = NSPoint(
                x: screenFrame.midX - panelWidth / 2,
                y: screenFrame.minY + Constants.UI.overlayBottomOffset
            )
        case .topCenter:
            origin = NSPoint(
                x: screenFrame.midX - panelWidth / 2,
                y: screenFrame.maxY - panelHeight - Constants.UI.overlayBottomOffset
            )
        case .nearCursor:
            let mouseLocation = NSEvent.mouseLocation
            origin = NSPoint(
                x: mouseLocation.x - panelWidth / 2,
                y: mouseLocation.y + 20
            )
        }
        panel.setFrameOrigin(origin)
    }
}
