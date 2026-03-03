# Alias Expansion & Emoji Support Implementation Plan

## Overview

Add a post-processing layer to TeleTalk's transcription pipeline that transforms text **after** ASR inference and **before** cursor insertion. This enables two features:

1. **Alias expansion** — user-defined text macros (e.g., "auq" → "you are allowed to ask me any questions")
2. **Emoji insertion** — say "emoji fire" to insert 🔥, using a bundled dictionary of ~200 common mappings with user overrides

These are **separate from PersonalDictionary** (which does acoustic boosting inside the ASR model). This is deterministic string replacement on confirmed output.

## Current State Analysis

**Pipeline today** (`AppDelegate.swift:191-202`):
```
transcriptionEngine.transcribe(samples:) → guard non-nil → textInserter.insert(text:)
```
There is zero transformation between transcription and insertion.

**PersonalDictionary** (`PersonalDictionary.swift`) stores `DictionaryTerm` with `text` + `aliases` fields. The aliases are forwarded to FluidAudio's `CustomVocabularyTerm` for acoustic biasing — not string replacement.

**Persistence pattern**: JSON files in `~/Library/Application Support/TeleTalk/` with `@MainActor @Observable` managers (`PersonalDictionary.swift`, `TranscriptionHistory.swift`).

**Settings pattern**: `NavigationSplitView` with `Tab` enum (`SettingsView.swift:11-31`). Each tab is a `Form` with `Section`s. Add/edit via `.sheet()` modals.

**State pattern**: Boolean toggles in `AppState` with `UserDefaults` + `didSet` persistence (`AppState.swift`).

**Environment injection**: Managers declared in `AppDelegate.swift:5-18`, passed via `.environment()` in `TeletalkApp.swift:17-24`.

## Desired End State

- User says "auq" → TeleTalk inserts "you are allowed to ask me any questions"
- User says "emoji fire" → TeleTalk inserts 🔥
- User says "send me an emoji thumbs up" → TeleTalk inserts "send me an 👍" (only "emoji thumbs up" triggers)
- Both features independently toggleable in Settings
- User can manage aliases (add/edit/delete) and custom emoji overrides in a new "Text Shortcuts" settings tab
- Bundled emoji dictionary covers ~200 common emoji with sensible keyword mappings
- TranscriptionHistory records the **expanded** text (what was actually inserted)

**Verification**: Build with `just build`, manual test by recording "auq" and "emoji fire", verify correct insertion.

## What We're NOT Doing

- Not modifying PersonalDictionary or acoustic boosting logic
- Not adding regex-based or fuzzy matching — exact whole-word matching only
- Not adding "auto-correct" or spell-check features
- Not adding emoji search/picker UI — just keyword-to-emoji expansion
- Not adding tests (no test suite exists per CLAUDE.md)
- Not adding emoji prefix customization (hardcoded "emoji" keyword for now)

## Implementation Approach

Follow existing patterns exactly: `@MainActor @Observable` manager with JSON persistence, `UserDefaults` toggles in `AppState`, new Settings tab, environment injection. The post-processor is a simple function called in `stopPipeline()` — not a separate class, since it's just two string replacements with no state machine or async logic.

## Phase 1: Data Models & Persistence

### Overview
Create the `TextShortcutManager` (alias CRUD + emoji dictionary loading) and add toggle settings to `AppState`.

### Changes Required

#### 1. File: `Teletalk/Utilities/Constants.swift` (Modify)
**Purpose**: Add constants for new file names and UserDefaults keys
**Changes**:
```swift
// Add to enum Defaults (after line 32):
static let aliasExpansionEnabled = "aliasExpansionEnabled"
static let emojiExpansionEnabled = "emojiExpansionEnabled"

// Add new enum (after Dictionary enum, line 46):
enum TextShortcuts {
    static let aliasFileName = "aliases.json"
    static let emojiFileName = "emoji-dictionary.json"  // bundled resource name
}
```

#### 2. File: `Teletalk/AppState.swift` (Modify)
**Purpose**: Add toggle settings for alias and emoji expansion
**Changes**: Add two new UserDefaults-backed properties following the existing `dictionaryEnabled` pattern:
```swift
var aliasExpansionEnabled: Bool = UserDefaults.standard
    .object(forKey: Constants.Defaults.aliasExpansionEnabled) as? Bool ?? true
{
    didSet {
        UserDefaults.standard.set(aliasExpansionEnabled, forKey: Constants.Defaults.aliasExpansionEnabled)
    }
}

var emojiExpansionEnabled: Bool = UserDefaults.standard
    .object(forKey: Constants.Defaults.emojiExpansionEnabled) as? Bool ?? true
{
    didSet {
        UserDefaults.standard.set(emojiExpansionEnabled, forKey: Constants.Defaults.emojiExpansionEnabled)
    }
}
```

#### 3. File: `Teletalk/Models/TextShortcutManager.swift` (Create)
**Purpose**: Manages user aliases and emoji dictionary with persistence
**Key Logic**:
```swift
import Foundation
import os

struct TextAlias: Identifiable, Codable, Equatable {
    let id: UUID
    var trigger: String    // e.g. "auq"
    var expansion: String  // e.g. "you are allowed to ask me any questions"

    init(trigger: String, expansion: String) {
        self.id = UUID()
        self.trigger = trigger
        self.expansion = expansion
    }
}

struct EmojiMapping: Codable {
    let keyword: String  // e.g. "fire"
    let emoji: String    // e.g. "🔥"
}

@MainActor
@Observable
final class TextShortcutManager {
    private let logger = Logger(subsystem: Constants.bundleIdentifier, category: "TextShortcuts")

    // User-defined aliases (persisted to JSON)
    private(set) var aliases: [TextAlias] = []

    // Merged emoji dictionary: bundled defaults + user overrides
    // Key = lowercase keyword, Value = emoji string
    private(set) var emojiDictionary: [String: String] = [:]

    // User's custom emoji overrides (persisted separately)
    private(set) var customEmoji: [EmojiMapping] = []

    init() {
        loadAliases()
        loadEmojiDictionary()
    }

    // MARK: - Alias CRUD

    func addAlias(_ alias: TextAlias) {
        aliases.append(alias)
        saveAliases()
    }

    func updateAlias(_ alias: TextAlias) {
        guard let idx = aliases.firstIndex(where: { $0.id == alias.id }) else { return }
        aliases[idx] = alias
        saveAliases()
    }

    func deleteAlias(_ alias: TextAlias) {
        aliases.removeAll { $0.id == alias.id }
        saveAliases()
    }

    // MARK: - Custom Emoji CRUD

    func addCustomEmoji(_ mapping: EmojiMapping) { ... }
    func deleteCustomEmoji(keyword: String) { ... }

    // MARK: - Text Processing

    /// Apply alias expansion: whole-word, case-insensitive replacement
    func expandAliases(in text: String) -> String {
        var result = text
        for alias in aliases {
            // Whole-word boundary match, case-insensitive
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: alias.trigger))\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: alias.expansion
                )
            }
        }
        return result
    }

    /// Apply emoji expansion: replace "emoji <keyword>" with the emoji character
    func expandEmoji(in text: String) -> String {
        // Match "emoji <keyword>" case-insensitively
        let pattern = "\\bemoji\\s+(\\w+(?:\\s+\\w+)?)\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return text
        }
        var result = text
        // Process matches in reverse to preserve indices
        let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in matches.reversed() {
            guard let keywordRange = Range(match.range(at: 1), in: result) else { continue }
            let keyword = String(result[keywordRange]).lowercased()
            if let emoji = emojiDictionary[keyword] {
                let fullRange = Range(match.range, in: result)!
                result.replaceSubrange(fullRange, with: emoji)
            }
        }
        return result
    }

    // MARK: - Persistence (private)
    // Follow PersonalDictionary pattern: JSON in ~/Library/Application Support/TeleTalk/
    // loadAliases(), saveAliases() — aliases.json
    // loadEmojiDictionary() — merge bundled emoji-dictionary.json + user custom overrides
}
```

#### 4. File: `Teletalk/Resources/emoji.json` (Create)
**Purpose**: Bundled emoji dictionary sourced from [github/gemoji](https://github.com/github/gemoji/blob/master/db/emoji.json)
**Format** (gemoji's format):
```json
[
    {"emoji": "😀", "description": "grinning face", "aliases": ["grinning"], "tags": ["smile", "happy"], ...},
    {"emoji": "🔥", "description": "fire", "aliases": ["fire"], "tags": ["burn"], ...},
    ...
]
```
We index by `aliases` + `tags` → emoji character. ~1,800 entries, ~180KB.
Must be added to the Xcode project's Copy Bundle Resources build phase.

**Lazy loading**: The emoji dictionary is NOT loaded on app launch. It is loaded only when `emojiExpansionEnabled` is toggled on (or was already on from a previous session). This avoids unnecessary memory use for users who don't use the feature.

### Success Criteria
- [ ] Automated: `just lint-check && just format-check`
- [ ] Automated: `just build`
- [ ] Manual: Verify `aliases.json` created in Application Support on first run
- [ ] Manual: Verify bundled `emoji-dictionary.json` loads correctly

### Dependencies
None — this phase is foundational.

---

## Phase 2: Pipeline Integration

### Overview
Wire `TextShortcutManager` into the transcription pipeline in `AppDelegate.stopPipeline()`.

### Changes Required

#### 1. File: `Teletalk/AppDelegate.swift` (Modify)
**Purpose**: Add TextShortcutManager as a property and inject post-processing into the pipeline

**Property declaration** (after line 9):
```swift
let textShortcutManager = TextShortcutManager()
```

**Pipeline injection** — insert between lines 201-202 (`appState.recordingState = .inserting` and `textInserter.insert`):
```swift
// Post-process transcription
var processedText = text
if appState.aliasExpansionEnabled {
    processedText = textShortcutManager.expandAliases(in: processedText)
}
if appState.emojiExpansionEnabled {
    processedText = textShortcutManager.expandEmoji(in: processedText)
}

appState.recordingState = .inserting
await textInserter.insert(text: processedText, method: appState.insertionMethod)
```

**History entry** — update to use `processedText` instead of `text` (line 205-210):
```swift
let entry = TranscriptionEntry(
    text: processedText,  // Record what was actually inserted
    audioDurationSeconds: audioDuration,
    modelVersion: appState.selectedModelVersion
)
```

#### 2. File: `Teletalk/TeletalkApp.swift` (Modify)
**Purpose**: Pass TextShortcutManager to Settings via environment

Add to Settings window environment chain (after line 23):
```swift
.environment(appDelegate.textShortcutManager)
```

### Success Criteria
- [ ] Automated: `just build`
- [ ] Manual: Add alias "auq" → "you are allowed to ask me any questions", record saying "auq", verify expanded text inserted
- [ ] Manual: Record saying "emoji fire", verify 🔥 inserted
- [ ] Manual: Verify history shows expanded text
- [ ] Manual: Toggle alias/emoji off in settings, verify no expansion occurs

### Dependencies
Phase 1 complete.

---

## Phase 3: Settings UI — Text Shortcuts Tab

### Overview
Add a new "Text Shortcuts" tab to the Settings window with sections for alias management and emoji configuration.

### Changes Required

#### 1. File: `Teletalk/UI/SettingsView.swift` (Modify)
**Purpose**: Add new tab and settings views

**Tab enum** — add case (after `dictionary`, line 15):
```swift
case shortcuts = "Shortcuts"
```

**Tab icon** — add case in `icon` computed property:
```swift
case .shortcuts: return "text.badge.plus"
```

**Tab routing** — add case in body switch (after `dictionary` case, line 46):
```swift
case .shortcuts: TextShortcutsSettingsView()
```

**New views** — add at end of file:

```swift
// MARK: - Text Shortcuts Settings

struct TextShortcutsSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(TextShortcutManager.self) private var shortcuts
    @State private var showingAddAlias = false

    var body: some View {
        @Bindable var state = appState

        Form {
            // Alias expansion section
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
                Text("Aliases replace exact words in transcription output. E.g. \"auq\" → \"you are allowed to ask me any questions\"")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            // Emoji expansion section
            Section {
                Toggle("Enable Emoji Expansion", isOn: $state.emojiExpansionEnabled)
                Text("Say \"emoji\" followed by a keyword to insert an emoji. E.g. \"emoji fire\" → 🔥")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
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
            }
        }
        .contextMenu {
            Button("Delete", role: .destructive) {
                shortcuts.deleteAlias(alias)
            }
        }
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
                    shortcuts.addAlias(TextAlias(trigger: trigger.trimmingCharacters(in: .whitespaces),
                                                 expansion: expansion))
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
```

### Success Criteria
- [ ] Automated: `just lint-check && just format-check`
- [ ] Automated: `just build`
- [ ] Manual: Open Settings → "Shortcuts" tab visible with correct icon
- [ ] Manual: Add alias via sheet, verify it appears in the list
- [ ] Manual: Delete alias via right-click context menu
- [ ] Manual: Toggle alias/emoji expansion on/off
- [ ] Manual: Close and reopen Settings → aliases persist

### Dependencies
Phase 1 complete. Phase 2 not strictly required but recommended for end-to-end testing.

---

## Phase 4: Bundled Emoji Dictionary

### Overview
Create the comprehensive emoji keyword dictionary and ensure it's bundled in the app.

### Changes Required

#### 1. File: `Teletalk/Resources/emoji-dictionary.json` (Create)
**Purpose**: ~200 common emoji mappings organized by category

Categories to cover:
- **Faces/Emotions**: smile, laugh, cry, wink, think, angry, love, cool, sick, sleep, scream, etc.
- **Gestures**: thumbs up, thumbs down, clap, wave, pray, muscle, point up, ok, peace, etc.
- **Hearts**: heart, broken heart, blue heart, green heart, etc.
- **Animals**: dog, cat, bear, monkey, unicorn, butterfly, etc.
- **Nature**: sun, moon, star, fire, rainbow, cloud, snow, rain, etc.
- **Food**: pizza, coffee, beer, cake, apple, etc.
- **Objects**: rocket, trophy, gift, bomb, bulb, key, etc.
- **Symbols**: check, cross, warning, question, exclamation, etc.
- **Activities**: party, celebrate, music, dance, etc.

Multi-word keywords supported: "thumbs up" → 👍, "broken heart" → 💔

#### 2. Xcode Project (Modify)
**Purpose**: Add `emoji-dictionary.json` to the app target's Copy Bundle Resources build phase so it's available at runtime via `Bundle.main`.

### Success Criteria
- [ ] Automated: `just build`
- [ ] Manual: Verify `Bundle.main.url(forResource: "emoji-dictionary", withExtension: "json")` returns non-nil
- [ ] Manual: Say "emoji rocket" → 🚀 inserted
- [ ] Manual: Say "emoji thumbs up" → 👍 inserted (multi-word keyword)
- [ ] Manual: Say "the emoji heart is great" → "the ❤️ is great" (mid-sentence expansion)

### Dependencies
Phase 1 complete.

---

## References

- **Injection point**: `AppDelegate.swift:201-202` — between `recordingState = .inserting` and `textInserter.insert()`
- **Persistence pattern**: `PersonalDictionary.swift` — JSON in Application Support with `@MainActor @Observable`
- **Settings tab pattern**: `SettingsView.swift:11-53` — Tab enum + NavigationSplitView
- **Toggle pattern**: `AppState.swift` — UserDefaults + didSet
- **Environment injection**: `TeletalkApp.swift:17-24` — `.environment()` chain
- **Manager declaration**: `AppDelegate.swift:5-18` — `let` properties
- **Constants pattern**: `Constants.swift` — nested enums for keys and file names
