import AVFoundation
import Cocoa

/// Checks and requests app permissions (microphone, accessibility).
@MainActor
enum Permissions {

    // MARK: - Microphone

    static func microphoneStatus() -> AppState.PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .granted
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .unknown
        @unknown default:
            return .unknown
        }
    }

    static func requestMicrophone() async -> AppState.PermissionStatus {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        return granted ? .granted : .denied
    }

    // MARK: - Accessibility

    static func accessibilityStatus() -> AppState.PermissionStatus {
        AXIsProcessTrusted() ? .granted : .denied
    }

    /// Prompts the user to grant accessibility access by opening System Settings.
    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - System Settings Deep Links

    static func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Refresh All

    /// Updates the given app state with current permission statuses.
    static func refreshAll(into appState: AppState) {
        appState.permissions.microphone = microphoneStatus()
        appState.permissions.accessibility = accessibilityStatus()
    }
}
