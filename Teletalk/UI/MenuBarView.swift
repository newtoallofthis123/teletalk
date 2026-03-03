import KeyboardShortcuts
import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(ModelManager.self) private var modelManager
    @Environment(AudioDeviceEnumerator.self) private var audioDeviceEnumerator

    var body: some View {
        // Status header
        VStack(alignment: .leading) {
            Label {
                HStack {
                    Text("TeleTalk")
                        .fontWeight(.medium)
                    Spacer()
                    Text(appState.statusText)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                    .symbolEffect(.pulse, isActive: appState.recordingState == .listening)
            }
        }

        Divider()

        // Active keybinds
        if appState.toggleShortcutEnabled, let shortcut = KeyboardShortcuts.getShortcut(for: .dictateToggle) {
            keybindRow(shortcut: shortcut, label: "Toggle")
        }
        if appState.holdShortcutEnabled, let shortcut = KeyboardShortcuts.getShortcut(for: .dictateHold) {
            keybindRow(shortcut: shortcut, label: "Hold to Talk")
        }

        Divider()

        // Context info
        let activeModel = modelManager.availableModels.first(where: { $0.status == .active })
        Text("Model: \(activeModel?.displayName ?? "None")")
            .foregroundStyle(.secondary)
            .font(.caption)
        Text("Input: \(selectedDeviceName)")
            .foregroundStyle(.secondary)
            .font(.caption)

        Divider()

        SettingsLink {
            Text("Settings...")
        }
        .keyboardShortcut(",")

        Divider()

        Button("Quit TeleTalk") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
        .task {
            appState.refreshPermissions()
        }
    }

    // MARK: - Helpers

    private func keybindRow(shortcut: KeyboardShortcuts.Shortcut, label: String) -> some View {
        HStack {
            Text(shortcut.description)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
            Text(label)
                .font(.caption)
        }
    }

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
