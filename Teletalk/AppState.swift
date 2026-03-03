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
        case inserting
        case error(String)
    }

    var recordingState: RecordingState = .idle

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

    // MARK: - Hotkey Mode

    enum HotkeyMode: String, CaseIterable {
        case holdToTalk
        case toggle

        var displayName: String {
            switch self {
            case .holdToTalk: return "Hold to Talk"
            case .toggle: return "Toggle"
            }
        }
    }

    var hotkeyMode: HotkeyMode = {
        let stored = UserDefaults.standard.string(forKey: Constants.Defaults.hotkeyMode) ?? HotkeyMode.holdToTalk.rawValue
        return HotkeyMode(rawValue: stored) ?? .holdToTalk
    }() {
        didSet {
            UserDefaults.standard.set(hotkeyMode.rawValue, forKey: Constants.Defaults.hotkeyMode)
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
        case .downloading(let progress):
            if progress < 0 {
                return "Downloading model…"
            }
            return "Downloading model… \(Int(progress * 100))%"
        case .error(let message):
            return "Error: \(message)"
        case .ready:
            break
        }
        switch recordingState {
        case .idle:
            return "Ready"
        case .listening:
            return "Listening…"
        case .transcribing:
            return "Transcribing…"
        case .inserting:
            return "Inserting text…"
        case .error(let message):
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
