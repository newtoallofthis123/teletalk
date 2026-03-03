import CoreAudio
import KeyboardShortcuts
import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(ModelManager.self) private var modelManager
    @Environment(AudioDeviceEnumerator.self) private var audioDeviceEnumerator
    @Environment(TranscriptionHistory.self) private var history
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // Status header
        Button {
            // Info-only row
        } label: {
            Label("TeleTalk — \(appState.statusText)", systemImage: statusIcon)
        }

        Divider()

        // Today's stats
        if !history.todayEntries.isEmpty {
            Button {} label: {
                Label(
                    "\(history.todayEntries.count) transcriptions · \(history.todayWordCount) words today",
                    systemImage: "chart.bar"
                )
            }

            Divider()
        }

        // Last 3 transcriptions — click to re-insert
        if !history.entries.isEmpty {
            ForEach(history.entries.prefix(3)) { entry in
                Button {
                    pasteText(entry.text)
                } label: {
                    let preview = entry.text.prefix(50) + (entry.text.count > 50 ? "…" : "")
                    Label(preview, systemImage: "text.quote")
                }
            }

            Divider()
        }

        // Active keybinds
        if appState.toggleShortcutEnabled, let shortcut = KeyboardShortcuts.getShortcut(for: .dictateToggle) {
            Button("\(shortcut.description)  Toggle") {}
        }
        if appState.holdShortcutEnabled, let shortcut = KeyboardShortcuts.getShortcut(for: .dictateHold) {
            Button("\(shortcut.description)  Hold to Talk") {}
        }

        Divider()

        // Model picker
        let activeModel = modelManager.availableModels.first(where: { $0.status == .active })
        Menu("Model: \(activeModel?.displayName ?? "None")") {
            ForEach(modelManager.availableModels) { model in
                Button {
                    Task {
                        _ = try? await modelManager.switchActiveModel(to: model.version, appState: appState)
                    }
                } label: {
                    HStack {
                        if model.status == .active {
                            Image(systemName: "checkmark")
                        }
                        switch model.status {
                        case .notDownloaded:
                            Text("\(model.displayName) (Not Downloaded)")
                        case .downloading:
                            Text("\(model.displayName) (Downloading…)")
                        default:
                            Text(model.displayName)
                        }
                    }
                }
                .disabled(
                    model.status == .notDownloaded
                        || model.status == .downloading
                        || model.status == .active
                        || appState.recordingState != .idle
                )
            }
        }

        // Input device picker
        Menu("Input: \(selectedDeviceName)") {
            Button {
                appState.selectedAudioDeviceUID = nil
            } label: {
                HStack {
                    if appState.selectedAudioDeviceUID == nil {
                        Image(systemName: "checkmark")
                    }
                    Text("System Default")
                }
            }

            Divider()

            ForEach(audioDeviceEnumerator.inputDevices) { device in
                Button {
                    appState.selectedAudioDeviceUID = device.uid
                } label: {
                    HStack {
                        if appState.selectedAudioDeviceUID == device.uid {
                            Image(systemName: "checkmark")
                        }
                        Image(systemName: deviceIcon(transport: device.transportType))
                        Text(device.name)
                    }
                }
            }
        }

        Divider()

        Button("Settings...") {
            NSApp.setActivationPolicy(.regular)
            openWindow(id: "settings")
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        .keyboardShortcut(",")

        Button("Quit TeleTalk") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    // MARK: - Helpers

    private func pasteText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        // Simulate Cmd+V to paste
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) // 'v'
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    private var selectedDeviceName: String {
        if let uid = appState.selectedAudioDeviceUID,
           let device = audioDeviceEnumerator.inputDevices.first(where: { $0.uid == uid })
        {
            return device.name
        }
        return "System Default"
    }

    private func deviceIcon(transport: UInt32) -> String {
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: return "laptopcomputer"
        case kAudioDeviceTransportTypeUSB: return "cable.connector"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "headphones"
        case kAudioDeviceTransportTypeAggregate: return "circle.grid.2x2"
        default: return "mic"
        }
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
