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

        // Force SwiftUI to re-evaluate by resetting the root view (fixes re-show bug)
        if let hostingView = panel?.contentView as? NSHostingView<OverlayView> {
            hostingView.rootView = OverlayView(appState: appState)
        }

        positionPanel(panel!)

        // Entrance animation: start transparent and offset, animate in
        let slideOffset: CGFloat = slideDirection()
        panel?.alphaValue = 0
        var origin = panel!.frame.origin
        origin.y -= slideOffset
        panel?.setFrameOrigin(origin)
        panel?.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel?.animator().alphaValue = 1
            var targetOrigin = panel!.frame.origin
            targetOrigin.y += slideOffset
            panel?.animator().setFrameOrigin(targetOrigin)
        }
    }

    func hide() {
        guard let panel else { return }
        let slideOffset: CGFloat = slideDirection()

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            var origin = panel.frame.origin
            origin.y -= slideOffset
            panel.animator().setFrameOrigin(origin)
        }, completionHandler: { [weak self] in
            self?.panel?.orderOut(nil)
            self?.panel?.alphaValue = 1
        })
    }

    // MARK: - Private

    /// Returns the vertical slide offset direction: positive = slide up from below, negative = slide down from above.
    private func slideDirection() -> CGFloat {
        switch appState.overlayPosition {
        case .bottomCenter, .nearCursor:
            return 20 // slide up from below
        case .topCenter:
            return -20 // slide down from above
        }
    }

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
