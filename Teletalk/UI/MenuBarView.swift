import KeyboardShortcuts
import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(ModelManager.self) private var modelManager
    @Environment(AudioDeviceEnumerator.self) private var audioDeviceEnumerator
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Status header
            HStack {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                    .symbolEffect(.pulse, isActive: appState.recordingState == .listening)
                Text("TeleTalk")
                    .fontWeight(.medium)
                Spacer()
                Text(appState.statusText)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider()

            // Active keybinds
            VStack(alignment: .leading, spacing: 4) {
                if appState.toggleShortcutEnabled, let shortcut = KeyboardShortcuts.getShortcut(for: .dictateToggle) {
                    keybindRow(shortcut: shortcut, label: "Toggle")
                }
                if appState.holdShortcutEnabled, let shortcut = KeyboardShortcuts.getShortcut(for: .dictateHold) {
                    keybindRow(shortcut: shortcut, label: "Hold to Talk")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            // Context info
            VStack(alignment: .leading, spacing: 2) {
                let activeModel = modelManager.availableModels.first(where: { $0.status == .active })
                Text("Model: \(activeModel?.displayName ?? "None")")
                Text("Input: \(selectedDeviceName)")
            }
            .foregroundStyle(.secondary)
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            // Actions
            VStack(spacing: 2) {
                Button {
                    openSettings()
                } label: {
                    HStack {
                        Text("Settings...")
                        Spacer()
                        Text("⌘,")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    HStack {
                        Text("Quit TeleTalk")
                        Spacer()
                        Text("⌘Q")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
            .padding(.vertical, 4)
        }
        .frame(width: 240)
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
