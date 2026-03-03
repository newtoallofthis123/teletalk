import CoreAudio
import KeyboardShortcuts
import LaunchAtLogin
import SwiftUI

// MARK: - Main Settings View

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    enum Tab: String, CaseIterable {
        case hotkeys = "Hotkeys"
        case audio = "Audio"
        case models = "Models"
        case dictionary = "Dictionary"
        case shortcuts = "Shortcuts"
        case ai = "AI"
        case general = "General"
        case history = "History"
        case permissions = "Permissions"

        var icon: String {
            switch self {
            case .hotkeys: return "keyboard"
            case .audio: return "waveform"
            case .models: return "brain"
            case .dictionary: return "character.book.closed"
            case .shortcuts: return "text.badge.plus"
            case .ai: return "sparkles"
            case .general: return "gear"
            case .history: return "clock.arrow.circlepath"
            case .permissions: return "lock.shield"
            }
        }

        /// Whether this tab should be shown given current system capabilities.
        var isVisible: Bool {
            switch self {
            case .ai:
                if #available(macOS 26, *) {
                    return AIPostProcessor.isAvailable
                }
                return false
            default:
                return true
            }
        }
    }

    @State private var selectedTab: Tab = .hotkeys

    private var visibleTabs: [Tab] {
        Tab.allCases.filter(\.isVisible)
    }

    var body: some View {
        NavigationSplitView {
            List(visibleTabs, id: \.self, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
            }
            .navigationSplitViewColumnWidth(min: 140, ideal: 160)
        } detail: {
            switch selectedTab {
            case .hotkeys: HotkeysSettingsView()
            case .audio: AudioSettingsView()
            case .models: ModelsSettingsView()
            case .dictionary: DictionarySettingsView()
            case .shortcuts: TextShortcutsSettingsView()
            case .ai:
                if #available(macOS 26, *) {
                    AISettingsView()
                }
            case .general: GeneralSettingsView()
            case .history: HistorySettingsView()
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
        ("30s", 30), ("60s", 60), ("2m", 120), ("5m", 300),
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
                Toggle("Speaker Diarization", isOn: $state.diarizationEnabled)

                switch appState.diarizationModelState {
                case .downloading:
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Downloading diarization models…")
                            .foregroundStyle(.secondary)
                    }
                case .ready:
                    Label("Diarization ready", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                case let .error(message):
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                case .idle:
                    EmptyView()
                }
            } header: {
                Label("Speaker Identification", systemImage: "person.2.wave.2")
                    .foregroundStyle(.secondary)
            } footer: {
                Text(
                    "Identifies different speakers in multi-person recordings. Downloads ~50-100 MB of models when first enabled."
                )
                .font(.caption)
                .foregroundStyle(.tertiary)
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
                    Stepper("", value: $state.minRecordingDuration, in: 0.1 ... 1.0, step: 0.1)
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
                Toggle("Audio Feedback", isOn: $state.audioFeedbackEnabled)
            } header: {
                Label("Sounds", systemImage: "speaker.wave.2")
                    .foregroundStyle(.secondary)
            } footer: {
                Text("Play a sound when recording starts and stops.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
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

// MARK: - History Tab

struct HistorySettingsView: View {
    @Environment(TranscriptionHistory.self) private var history
    @State private var searchText = ""

    private var filteredEntries: [TranscriptionEntry] {
        if searchText.isEmpty { return history.entries }
        return history.entries.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search transcriptions…", text: $searchText)
                    .textFieldStyle(.plain)

                if !history.entries.isEmpty {
                    Button("Clear All", role: .destructive) {
                        history.clearAll()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }
            .padding(8)

            Divider()

            if filteredEntries.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No Transcriptions Yet" : "No Results",
                    systemImage: searchText.isEmpty ? "text.bubble" : "magnifyingglass",
                    description: Text(searchText
                        .isEmpty ? "Your transcriptions will appear here." : "Try a different search.")
                )
            } else {
                List(filteredEntries) { entry in
                    HistoryEntryRow(entry: entry)
                }
            }
        }
    }
}

struct HistoryEntryRow: View {
    let entry: TranscriptionEntry
    @Environment(TranscriptionHistory.self) private var history

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.text)
                .lineLimit(3)

            HStack(spacing: 8) {
                Text(entry.timestamp, format: .relative(presentation: .named))
                Text("·")
                Text("\(entry.wordCount) words")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .contextMenu {
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.text, forType: .string)
            }
            Button("Delete", role: .destructive) {
                history.delete(entry)
            }
        }
    }
}

// MARK: - Dictionary Tab

struct DictionarySettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(PersonalDictionary.self) private var dictionary
    @State private var showingAddSheet = false

    var body: some View {
        @Bindable var state = appState

        Form {
            Section {
                Toggle("Enable Custom Vocabulary", isOn: $state.dictionaryEnabled)

                switch appState.vocabularyState {
                case .downloading:
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Downloading CTC model…")
                            .foregroundStyle(.secondary)
                    }
                case .ready:
                    Label("Vocabulary boosting active", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                case let .error(message):
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                case .idle:
                    EmptyView()
                }
            } header: {
                Label("Vocabulary Boosting", systemImage: "character.book.closed")
                    .foregroundStyle(.secondary)
            } footer: {
                Text(
                    "Uses a small CTC model (~64 MB) to bias transcription toward your terms. Requires slightly more memory."
                )
                .font(.caption)
                .foregroundStyle(.tertiary)
            }

            Section {
                if dictionary.terms.isEmpty {
                    Text("No custom terms yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(dictionary.terms) { term in
                        DictionaryTermRow(term: term)
                    }
                }

                Button("Add Term…") {
                    showingAddSheet = true
                }
            } header: {
                Label("Terms (\(dictionary.terms.count))", systemImage: "list.bullet")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingAddSheet) {
            AddTermSheet()
        }
    }
}

struct DictionaryTermRow: View {
    let term: DictionaryTerm
    @Environment(PersonalDictionary.self) private var dictionary
    @State private var showingEdit = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(term.text)
                    .fontWeight(.medium)
                if !term.aliases.isEmpty {
                    Text("Aliases: \(term.aliases.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button { showingEdit = true } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            Button(role: .destructive) { dictionary.delete(term) } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .sheet(isPresented: $showingEdit) {
            EditTermSheet(term: term)
        }
    }
}

struct EditTermSheet: View {
    let term: DictionaryTerm
    @Environment(PersonalDictionary.self) private var dictionary
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var aliasesText: String

    init(term: DictionaryTerm) {
        self.term = term
        _text = State(initialValue: term.text)
        _aliasesText = State(initialValue: term.aliases.joined(separator: ", "))
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Edit Term")
                .font(.headline)

            TextField("Term", text: $text)
                .textFieldStyle(.roundedBorder)

            TextField("Aliases, comma-separated (optional)", text: $aliasesText)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    let aliases = aliasesText
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    var updated = term
                    updated.text = text
                    updated.aliases = aliases
                    dictionary.update(updated)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 350)
    }
}

struct AddTermSheet: View {
    @Environment(PersonalDictionary.self) private var dictionary
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var aliasesText = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Custom Term")
                .font(.headline)

            TextField("Term (e.g. NVIDIA, macOS)", text: $text)
                .textFieldStyle(.roundedBorder)

            TextField("Aliases, comma-separated (optional)", text: $aliasesText)
                .textFieldStyle(.roundedBorder)

            Text("Aliases are common mishearings. E.g. for \"Häagen-Dazs\": Hagen Das, Hagen-Daz")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add") {
                    let aliases = aliasesText
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    dictionary.add(DictionaryTerm(text: text, aliases: aliases))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 350)
    }
}

// MARK: - Text Shortcuts Tab

struct TextShortcutsSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(TextShortcutManager.self) private var shortcuts
    @State private var showingAddAlias = false

    var body: some View {
        @Bindable var state = appState

        Form {
            Section {
                Toggle("Enable Alias Expansion", isOn: $state.aliasExpansionEnabled)

                if shortcuts.aliases.isEmpty {
                    Text("No aliases defined yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(shortcuts.aliases) { alias in
                        AliasRow(alias: alias)
                    }
                }

                Button("Add Alias…") {
                    showingAddAlias = true
                }
            } header: {
                Label("Aliases", systemImage: "arrow.right.arrow.left")
                    .foregroundStyle(.secondary)
            } footer: {
                Text(
                    "Aliases replace exact words in transcription output. " +
                        "E.g. \"auq\" → \"you are allowed to ask me any questions\""
                )
                .font(.caption)
                .foregroundStyle(.tertiary)
            }

            Section {
                Toggle("Enable Emoji Expansion", isOn: $state.emojiExpansionEnabled)
                    .onChange(of: appState.emojiExpansionEnabled) { _, enabled in
                        if enabled {
                            Task { await shortcuts.loadEmojiDictionaryIfNeeded() }
                        }
                    }

                if shortcuts.emojiLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Downloading emoji dictionary…")
                            .foregroundStyle(.secondary)
                    }
                } else if shortcuts.emojiLoaded {
                    Label(
                        "\(shortcuts.emojiDictionary.count) emoji loaded",
                        systemImage: "checkmark.circle.fill"
                    )
                    .foregroundStyle(.green)
                    .font(.caption)
                }

                Text("Say \"emoji\" followed by a keyword to insert an emoji. E.g. \"emoji fire\" → 🔥")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let cacheURL = shortcuts.emojiCacheURL {
                    Button("Browse Emoji Keywords…") {
                        NSWorkspace.shared.open(cacheURL)
                    }
                }
            } header: {
                Label("Emoji", systemImage: "face.smiling")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingAddAlias) {
            AddAliasSheet()
        }
    }
}

struct AliasRow: View {
    let alias: TextAlias
    @Environment(TextShortcutManager.self) private var shortcuts
    @State private var showingEdit = false

    var body: some View {
        HStack {
            Text(alias.trigger)
                .fontWeight(.medium)
                .font(.body.monospaced())
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
                .font(.caption)
            Text(alias.expansion)
                .lineLimit(1)
                .foregroundStyle(.secondary)
            Spacer()
            Button { showingEdit = true } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            Button(role: .destructive) { shortcuts.deleteAlias(alias) } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .sheet(isPresented: $showingEdit) {
            EditAliasSheet(alias: alias)
        }
    }
}

struct EditAliasSheet: View {
    let alias: TextAlias
    @Environment(TextShortcutManager.self) private var shortcuts
    @Environment(\.dismiss) private var dismiss
    @State private var trigger: String
    @State private var expansion: String

    init(alias: TextAlias) {
        self.alias = alias
        _trigger = State(initialValue: alias.trigger)
        _expansion = State(initialValue: alias.expansion)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Edit Alias")
                .font(.headline)

            TextField("Trigger word", text: $trigger)
                .textFieldStyle(.roundedBorder)

            TextField("Expands to…", text: $expansion)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    var updated = alias
                    updated.trigger = trigger.trimmingCharacters(in: .whitespaces)
                    updated.expansion = expansion
                    shortcuts.updateAlias(updated)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trigger.trimmingCharacters(in: .whitespaces).isEmpty || expansion.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }
}

struct AddAliasSheet: View {
    @Environment(TextShortcutManager.self) private var shortcuts
    @Environment(\.dismiss) private var dismiss
    @State private var trigger = ""
    @State private var expansion = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Alias")
                .font(.headline)

            TextField("Trigger word (e.g. auq)", text: $trigger)
                .textFieldStyle(.roundedBorder)

            TextField("Expands to…", text: $expansion)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add") {
                    shortcuts.addAlias(TextAlias(
                        trigger: trigger.trimmingCharacters(in: .whitespaces),
                        expansion: expansion
                    ))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trigger.trimmingCharacters(in: .whitespaces).isEmpty || expansion.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
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
