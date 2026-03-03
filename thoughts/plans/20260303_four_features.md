# Four Features: Audio Feedback, History Log, Rich Menu Bar, Personal Dictionary

## Overview

Four enhancements to bring TeleTalk closer to feature parity with WhisperFlow while preserving its local-first, zero-cloud identity. Ordered by dependency: audio feedback and history are independent foundations, rich menu bar builds on history data, and personal dictionary is the most architecturally involved (requires FluidAudio's CTC vocabulary boosting pipeline).

## Current State Analysis

- **Pipeline flow**: `startPipeline()` → `AudioRecorder` → `stopPipeline()` → `TranscriptionEngine.transcribe()` → `TextInserter.insert()` — all orchestrated in `AppDelegate.swift:111-173`
- **State**: Single `@Observable AppState` class holds all UI state, settings persisted via `UserDefaults` didSet observers — `AppState.swift:1-215`
- **Transcription**: `TranscriptionEngine.swift:36` calls `asrManager.transcribe(samples, source: .system)` with no vocabulary context
- **FluidAudio API**: `configureVocabularyBoosting(vocabulary:ctcModels:config:)` exists on `AsrManager` — must be called *before* `transcribe()`, then all subsequent calls auto-apply rescoring
- **Menu bar**: Simple status display with info-only buttons — `MenuBarView.swift:1-105`
- **Settings**: 5 tabs (hotkeys, audio, models, general, permissions) — `SettingsView.swift:1-457`
- **No sound effects, no transcription history, no session statistics exist**

## Desired End State

1. **Audio feedback**: Audible start/stop cues when recording begins and ends, toggleable in settings
2. **History log**: Searchable list of past transcriptions with timestamp, duration, text, and copy/re-insert actions — persisted to disk
3. **Rich menu bar**: Shows session stats (transcription count, total words today), quick model toggle, and history access
4. **Personal dictionary**: Users manage custom vocabulary terms (with aliases) in settings; FluidAudio's CTC-based vocabulary boosting is wired into the transcription pipeline

**Verification**: Build succeeds (`xcodebuild -scheme Teletalk`), all four features manually testable, no regressions in existing pipeline.

## What We're NOT Doing

- Streaming/partial transcription (different architecture)
- Voice commands ("new line", "period") — separate feature
- AI post-processing (LLM cleanup) — separate feature
- App-context awareness (detecting frontmost app)
- WPM counter (requires per-word timing math against audio duration — low value, noisy metric)
- Simple text replacement post-processing (can layer on later; CTC vocabulary boosting is the meaningful win)
- Unit tests (would be nice but no test infrastructure exists — separate initiative)

## Implementation Approach

Four phases, each independently shippable. Phases 1-3 are independent of each other. Phase 4 (personal dictionary) depends on nothing but is last because it's the most complex.

---

## Phase 1: Audio Feedback

### Overview
Play system sounds when recording starts and stops. Uses `NSSound` with bundled short audio files (or system sounds). Toggleable via a setting in the General tab.

### Changes Required

#### 1. File: `Teletalk/Utilities/Constants.swift` (Modify)
**Purpose**: Add UserDefaults key for audio feedback toggle
**Changes**:
```swift
// Inside enum Defaults, after overlayPosition:
static let audioFeedbackEnabled = "audioFeedbackEnabled"
```

#### 2. File: `Teletalk/AppState.swift` (Modify)
**Purpose**: Add audio feedback setting with UserDefaults persistence
**Changes**: Add after `overlayPosition` property (~line 155):
```swift
var audioFeedbackEnabled: Bool = UserDefaults.standard.object(forKey: Constants.Defaults.audioFeedbackEnabled) as? Bool ?? true {
    didSet {
        UserDefaults.standard.set(audioFeedbackEnabled, forKey: Constants.Defaults.audioFeedbackEnabled)
    }
}
```

#### 3. File: `Teletalk/Utilities/SoundEffect.swift` (Create)
**Purpose**: Thin wrapper that plays bundled or system sounds
**Key Logic**:
```swift
import AppKit

enum SoundEffect {
    case startRecording
    case stopRecording

    func play() {
        switch self {
        case .startRecording:
            NSSound(named: "Tink")?.play()    // short, unobtrusive system sound
        case .stopRecording:
            NSSound(named: "Pop")?.play()      // distinct from start
        }
    }
}
```

Note: `NSSound(named:)` with system sound names like "Tink", "Pop", "Purr", "Blow" works out of the box — no bundled audio files needed. If the user later wants custom sounds, we can add `.caf` files to the bundle and switch to `NSSound(contentsOf:byReference:)`.

#### 4. File: `Teletalk/AppDelegate.swift` (Modify)
**Purpose**: Play sounds at pipeline start/stop
**Changes**:
- In `startPipeline()` (~line 124, after `appState.recordingState = .listening`):
```swift
if appState.audioFeedbackEnabled { SoundEffect.startRecording.play() }
```
- In `stopPipeline()` (~line 142, after `appState.recordingState = .transcribing`):
```swift
if appState.audioFeedbackEnabled { SoundEffect.stopRecording.play() }
```

#### 5. File: `Teletalk/UI/SettingsView.swift` (Modify)
**Purpose**: Add audio feedback toggle to General tab
**Changes**: In `GeneralSettingsView`, add to the "Overlay" section or create a new "Feedback" section after it:
```swift
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
```

### Success Criteria
- [ ] Manual: Enable audio feedback → hold hotkey → hear start sound → release → hear stop sound
- [ ] Manual: Disable in settings → no sounds play
- [ ] Manual: Cancel with Escape → no stop sound (already handled — cancel doesn't call stopPipeline)
- [ ] Automated: `xcodebuild -project Teletalk.xcodeproj -scheme Teletalk -configuration Debug build`

---

## Phase 2: Transcription History Log

### Overview
Persist every successful transcription to a JSON file on disk. Add a History tab to Settings showing a scrollable, searchable list with copy and delete actions. Cap at 500 entries with automatic pruning.

### Changes Required

#### 1. File: `Teletalk/Utilities/Constants.swift` (Modify)
**Purpose**: Add history-related constants
**Changes**:
```swift
// Inside enum Constants
enum History {
    static let maxEntries = 500
    static let fileName = "history.json"
}
```

#### 2. File: `Teletalk/Models/TranscriptionHistory.swift` (Create)
**Purpose**: Data model and persistence for transcription history
**Key Logic**:
```swift
import Foundation
import os

struct TranscriptionEntry: Identifiable, Codable {
    let id: UUID
    let text: String
    let timestamp: Date
    let audioDurationSeconds: Double  // how long the user spoke
    let modelVersion: String

    init(text: String, audioDurationSeconds: Double, modelVersion: String) {
        self.id = UUID()
        self.text = text
        self.timestamp = Date()
        self.audioDurationSeconds = audioDurationSeconds
        self.modelVersion = modelVersion
    }

    var wordCount: Int {
        text.split(separator: " ").count
    }
}

@MainActor
@Observable
final class TranscriptionHistory {
    private let logger = Logger(subsystem: Constants.bundleIdentifier, category: "History")

    private(set) var entries: [TranscriptionEntry] = []

    private var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("TeleTalk", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(Constants.History.fileName)
    }

    init() {
        load()
    }

    func add(_ entry: TranscriptionEntry) {
        entries.insert(entry, at: 0)
        if entries.count > Constants.History.maxEntries {
            entries = Array(entries.prefix(Constants.History.maxEntries))
        }
        save()
    }

    func delete(_ entry: TranscriptionEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func clearAll() {
        entries.removeAll()
        save()
    }

    // MARK: - Today's stats (for menu bar)

    var todayEntries: [TranscriptionEntry] {
        entries.filter { Calendar.current.isDateInToday($0.timestamp) }
    }

    var todayWordCount: Int {
        todayEntries.reduce(0) { $0 + $1.wordCount }
    }

    // MARK: - Persistence

    private func save() {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Failed to save history: \(error.localizedDescription)")
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            entries = try JSONDecoder().decode([TranscriptionEntry].self, from: data)
        } catch {
            logger.error("Failed to load history: \(error.localizedDescription)")
        }
    }
}
```

#### 3. File: `Teletalk/AppDelegate.swift` (Modify)
**Purpose**: Record transcriptions to history after successful insertion
**Changes**:
- Add property: `let transcriptionHistory = TranscriptionHistory()`
- Pass as environment in `TeletalkApp.swift` (see below)
- In `stopPipeline()`, after successful text insertion (~line 157), before the "Done" sleep:
```swift
let sampleCount = samples.count
let audioDuration = Double(sampleCount) / Constants.Audio.sampleRate
let entry = TranscriptionEntry(
    text: text,
    audioDurationSeconds: audioDuration,
    modelVersion: appState.selectedModelVersion
)
transcriptionHistory.add(entry)
```

Note: `samples` is already in scope as a local in `stopPipeline()`. We need to capture `samples.count` before the `guard let samples` since we need it after transcription. Actually, `samples` is available — it's captured at line 134: `let samples = audioRecorder.stopRecording()` and used through the closure. We'll compute duration from `samples.count`.

#### 4. File: `Teletalk/TeletalkApp.swift` (Modify)
**Purpose**: Inject `TranscriptionHistory` as environment object
**Changes**: Add `.environment(appDelegate.transcriptionHistory)` alongside existing environment injections.

#### 5. File: `Teletalk/UI/SettingsView.swift` (Modify)
**Purpose**: Add History tab to settings
**Changes**:

Add `case history = "History"` to the `Tab` enum (with icon `"clock.arrow.circlepath"`), placed after `general`.

Add `HistorySettingsView`:
```swift
struct HistorySettingsView: View {
    @Environment(TranscriptionHistory.self) private var history
    @State private var searchText = ""

    private var filteredEntries: [TranscriptionEntry] {
        if searchText.isEmpty { return history.entries }
        return history.entries.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
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

            // Entry list
            if filteredEntries.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No Transcriptions Yet" : "No Results",
                    systemImage: searchText.isEmpty ? "text.bubble" : "magnifyingglass",
                    description: Text(searchText.isEmpty ? "Your transcriptions will appear here." : "Try a different search.")
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
                Text(entry.timestamp, style: .relative)
                Text("·")
                Text("\(entry.wordCount) words")
                Text("·")
                Text(String(format: "%.1fs", entry.audioDurationSeconds))
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
```

### Success Criteria
- [ ] Manual: Transcribe something → open History tab → entry appears with text, timestamp, word count, duration
- [ ] Manual: Right-click entry → Copy → paste into text editor → correct text
- [ ] Manual: Search filters entries correctly
- [ ] Manual: Quit and relaunch → history persists
- [ ] Manual: Clear All removes everything
- [ ] Automated: `xcodebuild -project Teletalk.xcodeproj -scheme Teletalk -configuration Debug build`

---

## Phase 3: Richer Menu Bar Status

### Overview
Enhance the menu bar dropdown to show today's session stats (transcription count, word count), provide a quick-glance last transcription preview, and add a button to open history directly.

### Changes Required

#### 1. File: `Teletalk/TeletalkApp.swift` (Modify)
**Purpose**: Ensure `TranscriptionHistory` is available in menu bar view's environment
**Changes**: Already handled in Phase 2 — the environment injection covers `MenuBarExtra` content too.

#### 2. File: `Teletalk/UI/MenuBarView.swift` (Modify)
**Purpose**: Add session stats, last transcription preview, and history shortcut
**Changes**: Replace the current menu bar view body with an enhanced version:

```swift
struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(ModelManager.self) private var modelManager
    @Environment(AudioDeviceEnumerator.self) private var audioDeviceEnumerator
    @Environment(TranscriptionHistory.self) private var history
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        // Status header
        Button {} label: {
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

            // Last transcription preview
            if let last = history.entries.first {
                Button {} label: {
                    Label {
                        Text(last.text)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    } icon: {
                        Image(systemName: "text.quote")
                    }
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
            openSettings()
        }
        .keyboardShortcut(",")

        Button("Quit TeleTalk") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    // ... (statusIcon, statusColor, selectedDeviceName helpers unchanged)
}
```

### Success Criteria
- [ ] Manual: Transcribe a few things → menu bar shows "N transcriptions · M words today"
- [ ] Manual: Last transcription text previewed (truncated) in menu
- [ ] Manual: Fresh day (no transcriptions) → stats section hidden
- [ ] Automated: `xcodebuild -project Teletalk.xcodeproj -scheme Teletalk -configuration Debug build`

---

## Phase 4: Personal Dictionary (Custom Vocabulary Boosting)

### Overview
Integrate FluidAudio's CTC-based vocabulary boosting. Users manage terms + aliases in a new "Dictionary" settings tab. On app launch (and whenever the dictionary changes), call `asrManager.configureVocabularyBoosting()` with the user's terms. This loads a small CTC model (~64 MB extra RAM) and applies acoustic-evidence-based rescoring to every subsequent `transcribe()` call.

**Key API insight**: Vocabulary is NOT passed per-call. Instead, `configureVocabularyBoosting()` is called once on the `AsrManager` instance, and all future `transcribe()` calls automatically use it. Call `disableVocabularyBoosting()` to turn it off.

### Changes Required

#### 1. File: `Teletalk/Utilities/Constants.swift` (Modify)
**Purpose**: Add dictionary-related constants and UserDefaults key
**Changes**:
```swift
// Inside enum Defaults
static let dictionaryEnabled = "dictionaryEnabled"

// Inside enum Constants
enum Dictionary {
    static let fileName = "dictionary.json"
}
```

#### 2. File: `Teletalk/Models/PersonalDictionary.swift` (Create)
**Purpose**: Data model and persistence for user's custom vocabulary terms
**Key Logic**:
```swift
import Foundation
import os

struct DictionaryTerm: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String          // The canonical form, e.g. "Häagen-Dazs"
    var aliases: [String]     // Common mishearings, e.g. ["Hagen Das", "Hagen-Daz"]

    init(text: String, aliases: [String] = []) {
        self.id = UUID()
        self.text = text
        self.aliases = aliases
    }
}

@MainActor
@Observable
final class PersonalDictionary {
    private let logger = Logger(subsystem: Constants.bundleIdentifier, category: "Dictionary")

    private(set) var terms: [DictionaryTerm] = []

    /// Fires whenever terms change so the transcription engine can reconfigure
    var onTermsChanged: (() -> Void)?

    private var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("TeleTalk", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(Constants.Dictionary.fileName)
    }

    init() {
        load()
    }

    func add(_ term: DictionaryTerm) {
        terms.append(term)
        save()
        onTermsChanged?()
    }

    func update(_ term: DictionaryTerm) {
        guard let idx = terms.firstIndex(where: { $0.id == term.id }) else { return }
        terms[idx] = term
        save()
        onTermsChanged?()
    }

    func delete(_ term: DictionaryTerm) {
        terms.removeAll { $0.id == term.id }
        save()
        onTermsChanged?()
    }

    // MARK: - Persistence

    private func save() {
        do {
            let data = try JSONEncoder().encode(terms)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Failed to save dictionary: \(error.localizedDescription)")
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            terms = try JSONDecoder().decode([DictionaryTerm].self, from: data)
        } catch {
            logger.error("Failed to load dictionary: \(error.localizedDescription)")
        }
    }
}
```

#### 3. File: `Teletalk/AppState.swift` (Modify)
**Purpose**: Add dictionary enabled toggle
**Changes**: Add after `audioFeedbackEnabled` (from Phase 1):
```swift
var dictionaryEnabled: Bool = UserDefaults.standard.object(forKey: Constants.Defaults.dictionaryEnabled) as? Bool ?? true {
    didSet {
        UserDefaults.standard.set(dictionaryEnabled, forKey: Constants.Defaults.dictionaryEnabled)
    }
}
```

#### 4. File: `Teletalk/Models/TranscriptionEngine.swift` (Modify)
**Purpose**: Add methods to configure/disable vocabulary boosting on the AsrManager
**Changes**: Add after existing `transcribe()` method:
```swift
/// Configure vocabulary boosting with user's personal dictionary terms.
/// Loads the CTC model (~64 MB) on first call. Subsequent calls reconfigure in-place.
func configureVocabulary(terms: [DictionaryTerm]) async throws {
    guard let asrManager else {
        throw TranscriptionError.notInitialized
    }

    guard !terms.isEmpty else {
        disableVocabulary()
        return
    }

    let vocabTerms = terms.map { term in
        CustomVocabularyTerm(
            text: term.text,
            aliases: term.aliases.isEmpty ? nil : term.aliases
        )
    }
    let context = CustomVocabularyContext(terms: vocabTerms)

    // Load CTC models (FluidAudio caches these after first load)
    let ctcModels = try await CtcModels.load()

    try await asrManager.configureVocabularyBoosting(
        vocabulary: context,
        ctcModels: ctcModels
    )

    logger.info("Vocabulary boosting configured with \(terms.count) terms")
}

/// Disable vocabulary boosting (no CTC overhead on transcribe calls).
func disableVocabulary() {
    asrManager?.disableVocabularyBoosting()
    logger.info("Vocabulary boosting disabled")
}
```

**Important**: The `CtcModels.load()` call may need adjustment based on the exact FluidAudio API. The research found `CtcModels` exists in `FluidAudio/ASR/CustomVocabulary/WordSpotting/CtcModels.swift` — we'll need to verify the exact initializer at build time. If `CtcModels` requires a model version or path, we'll adapt (e.g., `CtcModels.downloadAndLoad()` or similar pattern matching `AsrModels.downloadAndLoad()`).

#### 5. File: `Teletalk/AppDelegate.swift` (Modify)
**Purpose**: Wire up dictionary to transcription engine lifecycle
**Changes**:
- Add property: `let personalDictionary = PersonalDictionary()`
- In `applicationDidFinishLaunching`, after `transcriptionEngine.initialize()` (~line 39), add vocabulary setup:
```swift
// Configure vocabulary boosting if dictionary has terms
if appState.dictionaryEnabled && !personalDictionary.terms.isEmpty {
    try? await transcriptionEngine.configureVocabulary(terms: personalDictionary.terms)
}

// Listen for dictionary changes
personalDictionary.onTermsChanged = { [weak self] in
    guard let self else { return }
    Task { @MainActor in
        if self.appState.dictionaryEnabled && !self.personalDictionary.terms.isEmpty {
            try? await self.transcriptionEngine.configureVocabulary(terms: self.personalDictionary.terms)
        } else {
            self.transcriptionEngine.disableVocabulary()
        }
    }
}
```
- Pass `personalDictionary` as environment in `TeletalkApp.swift`

#### 6. File: `Teletalk/UI/SettingsView.swift` (Modify)
**Purpose**: Add Dictionary tab for managing vocabulary terms
**Changes**:

Add `case dictionary = "Dictionary"` to the `Tab` enum (icon: `"character.book.closed"` or `"text.book.closed"`), placed after `models`.

Add `DictionarySettingsView`:
```swift
struct DictionarySettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(PersonalDictionary.self) private var dictionary
    @State private var showingAddSheet = false

    var body: some View {
        @Bindable var state = appState

        Form {
            Section {
                Toggle("Enable Custom Vocabulary", isOn: $state.dictionaryEnabled)
            } header: {
                Label("Vocabulary Boosting", systemImage: "character.book.closed")
                    .foregroundStyle(.secondary)
            } footer: {
                Text("Uses a small CTC model (~64 MB) to bias transcription toward your terms. Requires slightly more memory.")
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

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(term.text)
                .fontWeight(.medium)
            if !term.aliases.isEmpty {
                Text("Aliases: \(term.aliases.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contextMenu {
            Button("Delete", role: .destructive) {
                dictionary.delete(term)
            }
        }
    }
}

struct AddTermSheet: View {
    @Environment(PersonalDictionary.self) private var dictionary
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var aliasesText = ""  // comma-separated

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
```

#### 7. File: `Teletalk/TeletalkApp.swift` (Modify)
**Purpose**: Inject `PersonalDictionary` into environment
**Changes**: Add `.environment(appDelegate.personalDictionary)` to both `MenuBarExtra` content and `Settings` scene.

### Success Criteria
- [ ] Manual: Add term "NVIDIA" with alias "in video" → transcribe "I work at NVIDIA" → output uses "NVIDIA" not "in video"
- [ ] Manual: Disable vocabulary boosting toggle → transcription runs without CTC overhead
- [ ] Manual: Delete a term → re-transcribe → term no longer boosted
- [ ] Manual: Empty dictionary → no CTC model loaded (check memory via Activity Monitor)
- [ ] Manual: App relaunch → dictionary terms persist
- [ ] Automated: `xcodebuild -project Teletalk.xcodeproj -scheme Teletalk -configuration Debug build`

### Risks & Open Questions

1. **`CtcModels.load()` exact API**: The research found the type exists but the exact initializer/factory method needs verification at build time. If it requires a version parameter or URL, adapt accordingly — the pattern should mirror `AsrModels.downloadAndLoad()`.
2. **CTC model download**: The CTC 110M model may need to be downloaded separately from the TDT model. If `CtcModels.load()` triggers a download, we should show a progress indicator (could reuse the model downloading state).
3. **Memory impact**: ~64 MB extra for CTC model. Fine on 8GB+ machines but worth noting in the settings UI footer.
4. **FluidAudio version**: Current checkout is pinned to commit `064daacd`. The `CustomVocabulary` directory exists in this checkout, so the API should be available. If not, we need to update the FluidAudio dependency to latest main.

---

## File Change Summary

| File | Action | Phase |
|------|--------|-------|
| `Utilities/Constants.swift` | Modify | 1, 2, 4 |
| `AppState.swift` | Modify | 1, 4 |
| `Utilities/SoundEffect.swift` | Create | 1 |
| `AppDelegate.swift` | Modify | 1, 2, 4 |
| `UI/SettingsView.swift` | Modify | 1, 2, 3, 4 |
| `Models/TranscriptionHistory.swift` | Create | 2 |
| `TeletalkApp.swift` | Modify | 2, 4 |
| `UI/MenuBarView.swift` | Modify | 3 |
| `Models/PersonalDictionary.swift` | Create | 4 |
| `Models/TranscriptionEngine.swift` | Modify | 4 |

**Files to create**: 3
**Files to modify**: 7

## References

- `AppDelegate.swift:111-173` — pipeline orchestration (start/stop/cancel)
- `AppState.swift:82-155` — settings with UserDefaults persistence pattern
- `TranscriptionEngine.swift:36` — current `transcribe()` call
- `MenuBarView.swift:1-105` — current menu bar implementation
- `SettingsView.swift:10-27` — tab enum pattern
- `ModelManager.swift:55-80` — model loading lifecycle (pattern for CTC model loading)
- FluidAudio `AsrManager.swift` — `configureVocabularyBoosting()` and `disableVocabularyBoosting()` methods
- FluidAudio `CustomVocabularyContext.swift` — `CustomVocabularyContext` and `CustomVocabularyTerm` structs
- FluidAudio `CtcModels.swift` — CTC model management
- FluidAudio `AsrTypes.swift` — `ASRResult` with `ctcDetectedTerms` and `ctcAppliedTerms` fields
