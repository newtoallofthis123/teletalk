import AppKit
import os
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let dictate = Self("dictate", default: .init(.space, modifiers: [.control, .shift]))
}

/// Manages global hotkey registration for hold-to-talk and toggle dictation modes.
@MainActor
final class HotkeyManager {

    private let logger = Logger(subsystem: Constants.bundleIdentifier, category: "HotkeyManager")

    private let appState: AppState
    private let onStartRecording: () -> Void
    private let onStopRecording: () -> Void

    /// Timestamp when key was pressed (for hold-to-talk debounce).
    private var keyDownTime: ContinuousClock.Instant?

    /// Minimum hold duration to count as intentional (not accidental tap).
    private let debounceThreshold: Duration = .milliseconds(200)

    init(appState: AppState, onStartRecording: @escaping () -> Void, onStopRecording: @escaping () -> Void) {
        self.appState = appState
        self.onStartRecording = onStartRecording
        self.onStopRecording = onStopRecording
    }

    /// Registers the global hotkey. Call after permissions are granted.
    func register() {
        logger.info("Registering hotkey")
        setupHandlers()
    }

    /// Unregisters the global hotkey.
    func unregister() {
        logger.info("Unregistering hotkey")
        KeyboardShortcuts.disable(KeyboardShortcuts.Name.dictate)
    }

    /// Re-registers handlers when hotkey mode changes.
    func updateMode() {
        unregister()
        setupHandlers()
    }

    // MARK: - Private

    private func setupHandlers() {
        // Hold-to-talk mode (default until dual keybinds in Phase B)
        KeyboardShortcuts.onKeyDown(for: .dictate) { [weak self] in
            Task { @MainActor in
                self?.handleHoldKeyDown()
            }
        }
        KeyboardShortcuts.onKeyUp(for: .dictate) { [weak self] in
            Task { @MainActor in
                self?.handleHoldKeyUp()
            }
        }

        logger.info("Hotkey handlers set up")
    }

    private func handleHoldKeyDown() {
        guard appState.recordingState == .idle else {
            logger.debug("Ignoring keyDown — not idle (state: \(String(describing: self.appState.recordingState)))")
            return
        }
        keyDownTime = ContinuousClock.now
        onStartRecording()
    }

    private func handleHoldKeyUp() {
        guard appState.recordingState == .listening else {
            logger.debug("Ignoring keyUp — not listening")
            return
        }

        // Debounce: ignore if held less than threshold (accidental tap).
        if let downTime = keyDownTime {
            let held = ContinuousClock.now - downTime
            if held < debounceThreshold {
                logger.info("Ignoring short press (\(held)) — below debounce threshold")
                keyDownTime = nil
                // Cancel the recording since it was too short
                onStopRecording()
                return
            }
        }

        keyDownTime = nil
        onStopRecording()
    }

    private func handleToggle() {
        switch appState.recordingState {
        case .idle:
            onStartRecording()
        case .listening:
            onStopRecording()
        default:
            logger.debug("Ignoring toggle — state is \(String(describing: self.appState.recordingState))")
        }
    }
}
