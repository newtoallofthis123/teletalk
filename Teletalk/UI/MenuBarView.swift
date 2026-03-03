import KeyboardShortcuts
import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(ModelManager.self) private var modelManager
    @Environment(AudioDeviceEnumerator.self) private var audioDeviceEnumerator
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        // Status header
        Button {
            // Info-only row
        } label: {
            Label("TeleTalk — \(appState.statusText)", systemImage: statusIcon)
        }

        Divider()

        // Active keybinds
        if appState.toggleShortcutEnabled, let shortcut = KeyboardShortcuts.getShortcut(for: .dictateToggle) {
            Button("\(shortcut.description)  Toggle") {}
        }
        if appState.holdShortcutEnabled, let shortcut = KeyboardShortcuts.getShortcut(for: .dictateHold) {
            Button("\(shortcut.description)  Hold to Talk") {}
        }

        Divider()

        // Context info
        let activeModel = modelManager.availableModels.first(where: { $0.status == .active })
        Button("Model: \(activeModel?.displayName ?? "None")") {}
        Button("Input: \(selectedDeviceName)") {}

        Divider()

        Button("Settings...") {
            openSettings()
        }
        .keyboardShortcut(",")

        Button("Quit TeleTalk") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    // MARK: - Helpers

    private var selectedDeviceName: String {
        if let uid = appState.selectedAudioDeviceUID,
           let device = audioDeviceEnumerator.inputDevices.first(where: { $0.uid == uid }) {
            return device.name
        }
        return "System Default"
    }

    private var statusIcon: String {
        switch appState.recordingState {
        case .listening:
            return "mic.fill"
        case .transcribing:
            return "waveform"
        case .error:
            return "exclamationmark.triangle.fill"
        default:
            break
        }
        if appState.permissions.microphone == .denied || appState.permissions.accessibility == .denied {
            return "exclamationmark.triangle.fill"
        }
        switch appState.modelState {
        case .downloading:
            return "arrow.down.circle"
        case .error:
            return "exclamationmark.triangle.fill"
        case .notDownloaded:
            return "arrow.down.circle"
        case .ready:
            break
        }
        return "checkmark.circle.fill"
    }

    private var statusColor: Color {
        if appState.permissions.microphone == .denied || appState.permissions.accessibility == .denied {
            return .orange
        }
        switch appState.modelState {
        case .error:
            return .red
        default:
            break
        }
        switch appState.recordingState {
        case .error:
            return .red
        case .listening:
            return .blue
        default:
            break
        }
        return .green
    }
}
