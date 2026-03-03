import CoreAudio
import SwiftUI
import KeyboardShortcuts
import LaunchAtLogin

// MARK: - Main Settings View

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    enum Tab: String, CaseIterable {
        case hotkeys = "Hotkeys"
        case audio = "Audio"
        case models = "Models"
        case general = "General"
        case permissions = "Permissions"

        var icon: String {
            switch self {
            case .hotkeys: return "keyboard"
            case .audio: return "waveform"
            case .models: return "brain"
            case .general: return "gear"
            case .permissions: return "lock.shield"
            }
        }
    }

    @State private var selectedTab: Tab = .hotkeys

    var body: some View {
        NavigationSplitView {
            List(Tab.allCases, id: \.self, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
            }
            .navigationSplitViewColumnWidth(min: 140, ideal: 160)
        } detail: {
            switch selectedTab {
            case .hotkeys: HotkeysSettingsView()
            case .audio: AudioSettingsView()
            case .models: ModelsSettingsView()
            case .general: GeneralSettingsView()
            case .permissions: PermissionsSettingsView()
            }
        }
        .frame(width: 550, height: 450)
    }
}

// MARK: - Hotkeys Tab

struct HotkeysSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        Form {
            Section {
                HStack {
                    Image(systemName: "command")
                        .foregroundStyle(.blue)
                        .frame(width: 20)
                    Text("Toggle")
                    Spacer()
                    KeyboardShortcuts.Recorder("", name: .dictateToggle)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                    Toggle("", isOn: $state.toggleShortcutEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .disabled(!appState.holdShortcutEnabled)
                }

                HStack {
                    Image(systemName: "hand.tap")
                        .foregroundStyle(.purple)
                        .frame(width: 20)
                    Text("Hold-to-talk")
                    Spacer()
                    KeyboardShortcuts.Recorder("", name: .dictateHold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                    Toggle("", isOn: $state.holdShortcutEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .disabled(!appState.toggleShortcutEnabled)
                }
            } header: {
                Label("Keyboard Shortcuts", systemImage: "keyboard")
                    .foregroundStyle(.secondary)
            } footer: {
                Text("At least one shortcut must remain enabled.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Audio Tab

struct AudioSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(AudioDeviceEnumerator.self) private var audioDevices

    private let durationOptions: [(String, Double)] = [
        ("30s", 30), ("60s", 60), ("2m", 120), ("5m", 300)
    ]

    var body: some View {
        @Bindable var state = appState

        Form {
            Section {
                Picker("Input Device", selection: $state.selectedAudioDeviceUID) {
                    Text("System Default").tag(nil as String?)
                    ForEach(audioDevices.inputDevices) { device in
                        HStack {
                            Image(systemName: deviceIcon(transport: device.transportType))
                            Text(device.name)
                            Text("(\(Int(device.sampleRate)) Hz)")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                        .tag(device.uid as String?)
                    }
                }
            } header: {
                Label("Input", systemImage: "mic")
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Max Recording", selection: $state.maxRecordingDuration) {
                    ForEach(durationOptions, id: \.1) { label, value in
                        Text(label).tag(value)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("Min Recording")
                    Spacer()
                    Text("\(Int(appState.minRecordingDuration * 1000)) ms")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Stepper("", value: $state.minRecordingDuration, in: 0.1...1.0, step: 0.1)
                        .labelsHidden()
                }
            } header: {
                Label("Duration", systemImage: "timer")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
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
}

// MARK: - Models Tab

struct ModelsSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(ModelManager.self) private var modelManager

    var body: some View {
        Form {
            Section {
                ForEach(modelManager.availableModels) { model in
                    ModelCardView(model: model)
                }
            } header: {
                Label("Available Models", systemImage: "brain")
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Text("Storage")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatBytes(modelManager.totalDiskUsage))
                        .monospacedDigit()
                }
                HStack {
                    Text("Location")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: modelManager.storageDirectory.path)
                    }
                    .buttonStyle(.link)
                }
            } header: {
                Label("Disk Usage", systemImage: "internaldrive")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

struct ModelCardView: View {
    let model: ModelInfo
    @Environment(AppState.self) private var appState
    @Environment(ModelManager.self) private var modelManager

    var body: some View {
        HStack {
            // Active indicator
            Image(systemName: model.status == .active ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(model.status == .active ? .green : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName)
                    .fontWeight(model.status == .active ? .semibold : .regular)
                HStack(spacing: 8) {
                    Text(model.languageDescription)
                    if let size = model.diskSize {
                        Text(formatBytes(size))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            statusView
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var statusView: some View {
        switch model.status {
        case .notDownloaded:
            Button("Download") {
                Task {
                    try? await modelManager.downloadModel(version: model.version)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

        case .downloading:
            ProgressView()
                .controlSize(.small)

        case .downloaded:
            HStack(spacing: 6) {
                Button("Activate") {
                    Task {
                        _ = try? await modelManager.switchActiveModel(to: model.version, appState: appState)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(appState.recordingState != .idle)

                Button(role: .destructive) {
                    try? modelManager.deleteModel(version: model.version)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }

        case .active:
            Text("Active")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.green)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(.green.opacity(0.1), in: Capsule())
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - General Tab

struct GeneralSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        Form {
            Section {
                LaunchAtLogin.Toggle("Launch at login")
            } header: {
                Label("Startup", systemImage: "power")
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Insertion Method", selection: $state.insertionMethod) {
                    ForEach(AppState.InsertionMethod.allCases, id: \.self) { method in
                        Text(method.displayName).tag(method)
                    }
                }
            } header: {
                Label("Text Input", systemImage: "text.cursor")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Show Overlay", isOn: $state.showOverlay)

                Picker("Position", selection: $state.overlayPosition) {
                    ForEach(AppState.OverlayPosition.allCases, id: \.self) { pos in
                        Text(pos.displayName).tag(pos)
                    }
                }
                .disabled(!appState.showOverlay)
            } header: {
                Label("Overlay", systemImage: "rectangle.on.rectangle")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Permissions Tab

struct PermissionsSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Form {
            Section {
                PermissionRow(
                    title: "Microphone",
                    icon: "mic.fill",
                    iconColor: .red,
                    status: appState.permissions.microphone,
                    action: Permissions.openMicrophoneSettings
                )

                PermissionRow(
                    title: "Accessibility",
                    icon: "accessibility",
                    iconColor: .blue,
                    status: appState.permissions.accessibility,
                    action: Permissions.openAccessibilitySettings
                )
            } header: {
                Label("Required Permissions", systemImage: "lock.shield")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task {
            appState.refreshPermissions()
        }
    }
}

struct PermissionRow: View {
    let title: String
    let icon: String
    let iconColor: Color
    let status: AppState.PermissionStatus
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
            }

            Text(title)

            Spacer()

            statusBadge

            if status == .denied {
                Button("Open Settings", action: action)
                    .buttonStyle(.link)
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch status {
        case .granted:
            Label("Granted", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .denied:
            Label("Denied", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        case .unknown:
            Label("Unknown", systemImage: "questionmark.circle")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }
}

// MARK: - Shared Badge (used by SetupView)

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
