import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading) {
            Label(appState.statusText, systemImage: statusIcon)
                .foregroundStyle(statusColor)
        }

        Divider()

        SettingsLink {
            Text("Settings...")
        }

        Divider()

        Button("Quit TeleTalk") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
        .task {
            appState.refreshPermissions()
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
            return .red
        default:
            break
        }
        return .green
    }
}
