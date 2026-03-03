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

        // Context info
        let activeModel = modelManager.availableModels.first(where: { $0.status == .active })
        Button("Model: \(activeModel?.displayName ?? "None")") {}
        Button("Input: \(selectedDeviceName)") {}

        Divider()

        Button("Settings...") {
            if let appDelegate = NSApp.delegate as? AppDelegate {
                appDelegate.showSettingsWindow()
            }
            openWindow(id: "settings")
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
