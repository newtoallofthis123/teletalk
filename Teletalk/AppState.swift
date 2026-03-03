import Foundation
import Observation
import SwiftUI

/// Central observable state for the entire app.
@MainActor
@Observable
final class AppState {
    // MARK: - Model State

    enum ModelState: Equatable {
        case notDownloaded
        case downloading(progress: Double)
        case ready
        case error(String)
    }

    var modelState: ModelState = .notDownloaded

    // MARK: - Recording State

    enum RecordingState: Equatable {
        case idle
        case listening
        case transcribing
        case enhancing
        case inserting
        case error(String)
    }

    var recordingState: RecordingState = .idle

    /// Real-time audio input level (RMS, 0…1) for waveform visualization.
    var audioLevel: Float = 0

    // MARK: - Permission State

    struct PermissionState: Equatable {
        var microphone: PermissionStatus = .unknown
        var accessibility: PermissionStatus = .unknown
    }

    enum PermissionStatus: Equatable {
        case unknown
        case granted
        case denied
    }

    var permissions = PermissionState()

    // MARK: - Setting Enums

    enum InsertionMethod: String, CaseIterable {
        case auto
        case accessibilityOnly
        case clipboardOnly

        var displayName: String {
            switch self {
            case .auto: return "Auto"
            case .accessibilityOnly: return "Accessibility Only"
            case .clipboardOnly: return "Clipboard Only"
            }
        }
    }

    enum OverlayPosition: String, CaseIterable {
        case bottomCenter
        case topCenter
        case nearCursor

        var displayName: String {
            switch self {
            case .bottomCenter: return "Bottom Center"
            case .topCenter: return "Top Center"
            case .nearCursor: return "Near Cursor"
            }
        }
    }

    // MARK: - Hotkey Settings

    var toggleShortcutEnabled: Bool = UserDefaults.standard
        .object(forKey: Constants.Defaults.toggleShortcutEnabled) as? Bool ?? true
    {
        didSet {
            if !toggleShortcutEnabled, !holdShortcutEnabled {
                toggleShortcutEnabled = true
                return
            }
            UserDefaults.standard.set(toggleShortcutEnabled, forKey: Constants.Defaults.toggleShortcutEnabled)
        }
    }

    var holdShortcutEnabled: Bool = UserDefaults.standard
        .object(forKey: Constants.Defaults.holdShortcutEnabled) as? Bool ?? true
    {
        didSet {
            if !holdShortcutEnabled, !toggleShortcutEnabled {
                holdShortcutEnabled = true
                return
            }
            UserDefaults.standard.set(holdShortcutEnabled, forKey: Constants.Defaults.holdShortcutEnabled)
        }
    }

    // MARK: - Audio Settings

    var selectedAudioDeviceUID: String? = UserDefaults.standard
        .string(forKey: Constants.Defaults.selectedAudioDeviceUID)
    {
        didSet {
            UserDefaults.standard.set(selectedAudioDeviceUID, forKey: Constants.Defaults.selectedAudioDeviceUID)
        }
    }

    var maxRecordingDuration: Double = UserDefaults.standard
        .object(forKey: Constants.Defaults.maxRecordingDuration) as? Double ?? 120
    {
        didSet {
            UserDefaults.standard.set(maxRecordingDuration, forKey: Constants.Defaults.maxRecordingDuration)
        }
    }

    var minRecordingDuration: Double = UserDefaults.standard
        .object(forKey: Constants.Defaults.minRecordingDuration) as? Double ?? 0.2
    {
        didSet {
            UserDefaults.standard.set(minRecordingDuration, forKey: Constants.Defaults.minRecordingDuration)
        }
    }

    // MARK: - Model Settings

    var selectedModelVersion: String = UserDefaults.standard
        .string(forKey: Constants.Defaults.selectedModelVersion) ?? "v2"
    {
        didSet {
            UserDefaults.standard.set(selectedModelVersion, forKey: Constants.Defaults.selectedModelVersion)
        }
    }

    // MARK: - General Settings

    var insertionMethod: InsertionMethod = {
        let stored = UserDefaults.standard.string(forKey: Constants.Defaults.insertionMethod) ?? InsertionMethod.auto
            .rawValue
        return InsertionMethod(rawValue: stored) ?? .auto
    }() {
        didSet {
            UserDefaults.standard.set(insertionMethod.rawValue, forKey: Constants.Defaults.insertionMethod)
        }
    }

    var showOverlay: Bool = UserDefaults.standard.object(forKey: Constants.Defaults.showOverlay) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(showOverlay, forKey: Constants.Defaults.showOverlay)
        }
    }

    var overlayPosition: OverlayPosition = {
        let stored = UserDefaults.standard.string(forKey: Constants.Defaults.overlayPosition) ?? OverlayPosition
            .bottomCenter.rawValue
        return OverlayPosition(rawValue: stored) ?? .bottomCenter
    }() {
        didSet {
            UserDefaults.standard.set(overlayPosition.rawValue, forKey: Constants.Defaults.overlayPosition)
        }
    }

    // MARK: - Feedback Settings

    var audioFeedbackEnabled: Bool = UserDefaults.standard
        .object(forKey: Constants.Defaults.audioFeedbackEnabled) as? Bool ?? true
    {
        didSet {
            UserDefaults.standard.set(audioFeedbackEnabled, forKey: Constants.Defaults.audioFeedbackEnabled)
        }
    }

    // MARK: - Dictionary Settings

    var vocabularyState: VocabularyState = .idle

    enum VocabularyState: Equatable {
        case idle
        case downloading
        case ready
        case error(String)
    }

    var onDictionaryEnabledChanged: (() -> Void)?

    var dictionaryEnabled: Bool = UserDefaults.standard
        .object(forKey: Constants.Defaults.dictionaryEnabled) as? Bool ?? true
    {
        didSet {
            UserDefaults.standard.set(dictionaryEnabled, forKey: Constants.Defaults.dictionaryEnabled)
            onDictionaryEnabledChanged?()
        }
    }

    // MARK: - Text Shortcut Settings

    var aliasExpansionEnabled: Bool = UserDefaults.standard
        .object(forKey: Constants.Defaults.aliasExpansionEnabled) as? Bool ?? true
    {
        didSet {
            UserDefaults.standard.set(aliasExpansionEnabled, forKey: Constants.Defaults.aliasExpansionEnabled)
        }
    }

    var emojiExpansionEnabled: Bool = UserDefaults.standard
        .object(forKey: Constants.Defaults.emojiExpansionEnabled) as? Bool ?? true
    {
        didSet {
            UserDefaults.standard.set(emojiExpansionEnabled, forKey: Constants.Defaults.emojiExpansionEnabled)
        }
    }

    // MARK: - AI Enhancement Settings

    var aiEnhancementEnabled: Bool = UserDefaults.standard
        .object(forKey: Constants.Defaults.aiEnhancementEnabled) as? Bool ?? false
    {
        didSet {
            UserDefaults.standard.set(aiEnhancementEnabled, forKey: Constants.Defaults.aiEnhancementEnabled)
        }
    }

    var aiSystemPrompt: String = UserDefaults.standard
        .string(forKey: Constants.Defaults.aiSystemPrompt) ?? Constants.AI.defaultSystemPrompt
    {
        didSet {
            UserDefaults.standard.set(aiSystemPrompt, forKey: Constants.Defaults.aiSystemPrompt)
        }
    }

    // MARK: - Computed

    /// Human-readable status for the menu bar.
    var statusText: String {
        if permissions.microphone == .denied {
            return "No mic access"
        }
        if permissions.accessibility == .denied {
            return "No accessibility access"
        }
        switch modelState {
        case .notDownloaded:
            return "Model not downloaded"
        case let .downloading(progress):
            if progress < 0 {
                return "Downloading model…"
            }
            return "Downloading model… \(Int(progress * 100))%"
        case let .error(message):
            return "Error: \(message)"
        case .ready:
            break
        }
        if vocabularyState == .downloading {
            return "Downloading CTC model…"
        }
        switch recordingState {
        case .idle:
            return "Ready"
        case .listening:
            return "Listening…"
        case .transcribing:
            return "Transcribing…"
        case .enhancing:
            return "Enhancing…"
        case .inserting:
            return "Inserting text…"
        case let .error(message):
            return "Error: \(message)"
        }
    }

    // MARK: - Permission Refresh

    /// Refreshes all permission states. Call on app launch and when returning from Settings.
    func refreshPermissions() {
        Permissions.refreshAll(into: self)
    }

    /// Requests missing permissions on launch. Shows system prompts for mic and accessibility.
    func requestPermissionsOnLaunch() async {
        // Microphone — system dialog
        if permissions.microphone != .granted {
            permissions.microphone = await Permissions.requestMicrophone()
        }
        // Accessibility — system prompt to open Settings
        if permissions.accessibility != .granted {
            Permissions.requestAccessibility()
            // Re-check after a short delay (user may have granted it)
            try? await Task.sleep(for: .seconds(1))
            permissions.accessibility = Permissions.accessibilityStatus()
        }
    }
}
