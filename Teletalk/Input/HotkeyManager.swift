import AppKit
import os
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let dictateToggle = Self("dictateToggle", default: .init(.space, modifiers: [.control, .shift]))
    static let dictateHold = Self("dictateHold", default: .init(.l, modifiers: [.control, .shift]))
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

    /// Registers both global hotkeys. Call after permissions are granted.
    func register() {
        logger.info("Registering hotkeys")
        setupHandlers()
    }

    /// Unregisters all global hotkeys.
    func unregister() {
        logger.info("Unregistering hotkeys")
        KeyboardShortcuts.disable(.dictateToggle)
        KeyboardShortcuts.disable(.dictateHold)
    }

    /// Re-registers handlers when enable states change.
    func refreshHandlers() {
        unregister()
        setupHandlers()
    }

    // MARK: - Private

    private func setupHandlers() {
        if appState.toggleShortcutEnabled {
            KeyboardShortcuts.onKeyDown(for: .dictateToggle) { [weak self] in
                Task { @MainActor in
                    self?.handleToggle()
                }
            }
        }

        if appState.holdShortcutEnabled {
            KeyboardShortcuts.onKeyDown(for: .dictateHold) { [weak self] in
                Task { @MainActor in
                    self?.handleHoldKeyDown()
                }
            }
            KeyboardShortcuts.onKeyUp(for: .dictateHold) { [weak self] in
                Task { @MainActor in
                    self?.handleHoldKeyUp()
                }
            }
        }

        logger.info("Hotkey handlers set up (toggle: \(self.appState.toggleShortcutEnabled), hold: \(self.appState.holdShortcutEnabled))")
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
