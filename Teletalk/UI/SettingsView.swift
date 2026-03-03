import SwiftUI
import KeyboardShortcuts
import LaunchAtLogin

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            PermissionsSettingsView()
                .tabItem {
                    Label("Permissions", systemImage: "lock.shield")
                }
        }
        .frame(width: 450, height: 300)
    }
}

struct GeneralSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        Form {
            Section("Hotkeys") {
                KeyboardShortcuts.Recorder("Toggle:", name: .dictateToggle)
                KeyboardShortcuts.Recorder("Hold-to-talk:", name: .dictateHold)
            }

            Section("General") {
                LaunchAtLogin.Toggle("Launch at login")

                AudioDevicePicker()
            }
        }
        .padding()
    }
}

struct PermissionsSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Form {
            Section("Permissions") {
                HStack {
                    Label("Microphone", systemImage: "mic.fill")
                    Spacer()
                    PermissionBadge(status: appState.permissions.microphone)
                    if appState.permissions.microphone == .denied {
                        Button("Open Settings") {
                            Permissions.openMicrophoneSettings()
                        }
                        .buttonStyle(.link)
                    }
                }

                HStack {
                    Label("Accessibility", systemImage: "accessibility")
                    Spacer()
                    PermissionBadge(status: appState.permissions.accessibility)
                    if appState.permissions.accessibility == .denied {
                        Button("Open Settings") {
                            Permissions.openAccessibilitySettings()
                        }
                        .buttonStyle(.link)
                    }
                }
            }

            Section("Model") {
                HStack {
                    Label("Transcription Model", systemImage: "brain")
                    Spacer()
                    switch appState.modelState {
                    case .notDownloaded:
                        Text("Not downloaded").foregroundStyle(.secondary)
                    case .downloading(let progress):
                        ProgressView(value: progress)
                            .frame(width: 100)
                    case .ready:
                        Text("Ready").foregroundStyle(.green)
                    case .error(let msg):
                        Text(msg).foregroundStyle(.red).lineLimit(1)
                    }
                }
            }
        }
        .padding()
        .task {
            appState.refreshPermissions()
        }
    }
}

struct PermissionBadge: View {
    let status: AppState.PermissionStatus

    var body: some View {
        switch status {
        case .granted:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .denied:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        case .unknown:
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.secondary)
        }
    }
}

struct AudioDevicePicker: View {
    @State private var selectedDeviceUID: String = UserDefaults.standard.string(forKey: Constants.Defaults.selectedAudioDeviceUID) ?? "default"

    var body: some View {
        Picker("Audio Input", selection: $selectedDeviceUID) {
            Text("System Default").tag("default")
            // Audio device enumeration requires CoreAudio HAL APIs.
            // For MVP, we use the system default input device.
        }
        .onChange(of: selectedDeviceUID) { _, newValue in
            UserDefaults.standard.set(newValue, forKey: Constants.Defaults.selectedAudioDeviceUID)
        }
    }
}
