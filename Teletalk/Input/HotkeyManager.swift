import AppKit
import KeyboardShortcuts
import os

extension KeyboardShortcuts.Name {
    static let dictateToggle = Self("dictateToggle", default: .init(.space, modifiers: [.control, .shift]))
    static let dictateHold = Self("dictateHold", default: .init(.l, modifiers: [.control, .shift]))
    static let dictateAI = Self("dictateAI")
}

/// Manages global hotkey registration for hold-to-talk and toggle dictation modes.
@MainActor
final class HotkeyManager {
    private let logger = Logger(subsystem: Constants.bundleIdentifier, category: "HotkeyManager")

    private let appState: AppState
    private let onStartRecording: () -> Void
    private let onStopRecording: () -> Void
    private let onCancel: () -> Void

    /// Whether the last hotkey trigger was the AI-enhanced dictation key.
    var lastTriggerWasAI: Bool = false

    private var escapeMonitor: Any?

    /// Timestamp when key was pressed (for hold-to-talk debounce).
    private var keyDownTime: ContinuousClock.Instant?

    /// Minimum hold duration to count as intentional (not accidental tap).
    private let debounceThreshold: Duration = .milliseconds(200)

    init(
        appState: AppState,
        onStartRecording: @escaping () -> Void,
        onStopRecording: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.appState = appState
        self.onStartRecording = onStartRecording
        self.onStopRecording = onStopRecording
        self.onCancel = onCancel
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
        KeyboardShortcuts.disable(.dictateAI)
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
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

        // AI-enhanced dictation hotkey (toggle-only, always registered — gated at invocation)
        KeyboardShortcuts.onKeyDown(for: .dictateAI) { [weak self] in
            Task { @MainActor in
                self?.handleAIToggle()
            }
        }

        // Escape key monitor for cancellation during active pipeline
        escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch appState.recordingState {
                case .listening, .transcribing, .enhancing:
                    logger.info("Escape pressed — cancelling pipeline")
                    onCancel()
                default:
                    break
                }
            }
        }

        let toggle = self.appState.toggleShortcutEnabled
        let hold = self.appState.holdShortcutEnabled
        logger.info("Hotkey handlers set up (toggle: \(toggle), hold: \(hold))")
    }

    private func handleAIToggle() {
        guard appState.aiEnhancementEnabled else {
            logger.debug("Ignoring AI hotkey — AI enhancement not enabled")
            return
        }
        switch appState.recordingState {
        case .idle:
            lastTriggerWasAI = true
            onStartRecording()
        case .listening:
            onStopRecording()
        default:
            logger.debug("Ignoring AI toggle — state is \(String(describing: self.appState.recordingState))")
        }
    }

    private func handleHoldKeyDown() {
        guard appState.recordingState == .idle else {
            logger.debug("Ignoring keyDown — not idle (state: \(String(describing: self.appState.recordingState)))")
            return
        }
        lastTriggerWasAI = false
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
            lastTriggerWasAI = false
            onStartRecording()
        case .listening:
            onStopRecording()
        default:
            logger.debug("Ignoring toggle — state is \(String(describing: self.appState.recordingState))")
        }
    }
}
