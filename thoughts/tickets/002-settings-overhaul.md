# Ticket 002: Settings Overhaul & Model Manager

## Goal

Redesign the settings window with richer configuration, dual keybinds (toggle + hold), a model manager for downloading/switching models, proper audio device enumeration, and sidebar navigation.

## Current State

Settings is a 450x300 TabView with 2 tabs:
- **General**: single hotkey recorder, mode picker (hold vs toggle), launch-at-login, non-functional audio device picker
- **Permissions**: mic/accessibility badges, model download status

Everything else is hardcoded: model (Parakeet TDT v2 only), audio device (system default), recording limits, insertion strategy.

## Changes

### 1. Window Layout: Sidebar Navigation

Replace the top tab bar with a sidebar (`NavigationSplitView` or similar), ~550x450. Sections:

- **Hotkeys**
- **Audio**
- **Models**
- **General**
- **Permissions** (keep, but model status moves to Models)

### 2. Hotkeys Tab — Dual Keybinds

Replace the single shortcut + mode picker with two independent keybinds:

| Control | Description |
|---------|-------------|
| **Toggle shortcut** | `KeyboardShortcuts.Recorder` — press to start, press again to stop |
| **Hold shortcut** | `KeyboardShortcuts.Recorder` — hold to record, release to transcribe |
| **Enable toggles** | Each keybind gets an individual enable/disable toggle |
| **Constraint** | At least one keybind must be enabled at all times (disable the toggle on the last active one) |

Implementation notes:
- Register two `KeyboardShortcuts.Name` values (`.dictateToggle`, `.dictateHold`)
- `HotkeyManager` registers handlers for both simultaneously
- Remove `HotkeyMode` enum and the mode picker — mode is now implicit per keybind
- Debounce threshold (200ms) stays hardcoded for hold mode

### 3. Audio Tab

| Control | Description |
|---------|-------------|
| **Input device picker** | Enumerate real devices via CoreAudio HAL (`AudioObjectGetPropertyData` with `kAudioHardwarePropertyDevices`). Show device name + sample rate. Include "System Default" option. |
| **Max recording duration** | Slider or stepper: 30s / 60s / 120s / 300s (default 120s) |
| **Min recording duration** | Stepper: 100ms–1000ms (default 200ms) |

Persist selections in UserDefaults. `AudioRecorder` reads selected device UID and uses it instead of always grabbing the default input node.

Device enumeration approach:
- Use `CoreAudio` framework: `AudioObjectGetPropertyData` with `kAudioHardwarePropertyDevices`
- Get device name via `kAudioObjectPropertyName`
- Get device UID via `kAudioDevicePropertyDeviceUID`
- Filter to input-capable devices (`kAudioDevicePropertyStreamConfiguration`)
- Listen for `kAudioHardwarePropertyDevices` changes to update list live

### 4. Models Tab — Model Manager

This is the main new feature. Shows installed and available models with download/delete controls.

**Available models from FluidAudio:**

| Model | Enum/Repo | Languages | Notes |
|-------|-----------|-----------|-------|
| Parakeet TDT v2 | `AsrModelVersion.v2` | English | Currently used, 6% WER |
| Parakeet TDT v3 | `AsrModelVersion.v3` | 25+ languages | FluidAudio default |

**UI layout:**

```
┌─────────────────────────────────────────┐
│ Models                                  │
│                                         │
│ ┌─────────────────────────────────────┐ │
│ │ ● Parakeet TDT v2        [Active]  │ │
│ │   English · 600MB · Downloaded      │ │
│ │   [Delete]                          │ │
│ ├─────────────────────────────────────┤ │
│ │ ○ Parakeet TDT v3                  │ │
│ │   25+ Languages · Not Downloaded    │ │
│ │   [Download]                        │ │
│ └─────────────────────────────────────┘ │
│                                         │
│ Storage: ~/Library/.../Models/          │
│ Total: 600 MB used                      │
│ [Reveal in Finder]                      │
└─────────────────────────────────────────┘
```

**Behavior:**
- Download button shows progress (FluidAudio doesn't give granular progress, so use indeterminate spinner)
- Switching active model: download if needed → load → set as active
- Delete: remove cached files, update state to `.notDownloaded`
- Persist selected model version in UserDefaults
- `ModelManager` updated to accept a version parameter
- Only one model active at a time
- Show disk usage per model (scan directory size)

### 5. General Tab

| Control | Description |
|---------|-------------|
| **Launch at login** | Existing `LaunchAtLogin.Toggle` |
| **Text insertion method** | Picker: Auto (default) / Accessibility Only / Clipboard Only |
| **Show overlay** | Toggle to hide the floating recording pill |
| **Overlay position** | Picker: Bottom Center (default) / Top Center / Near Cursor |

Persist all in UserDefaults. Wire into `TextInserter` and `OverlayWindow`.

### 6. Permissions Tab

Keep existing mic + accessibility badges. Remove model status (moved to Models tab).

## Files to Change

| File | Change |
|------|--------|
| `UI/SettingsView.swift` | Full rewrite — sidebar nav, new tab views, visual polish |
| `UI/MenuBarView.swift` | Redesign — show keybinds, model, device, colored status |
| `Input/HotkeyManager.swift` | Support two simultaneous keybinds, remove mode-based branching |
| `AppState.swift` | Remove `HotkeyMode`, add new persisted settings (selected model, insertion method, overlay prefs, audio device, recording limits, keybind enable states) |
| `Models/ModelManager.swift` | Accept version param, support multiple cached models, delete, disk usage |
| `Audio/AudioRecorder.swift` | Use selected audio device instead of default, read recording limits from AppState |
| `Input/TextInserter.swift` | Respect insertion method preference |
| `UI/OverlayWindow.swift` | Respect show/hide and position prefs |
| `Utilities/Constants.swift` | Move hardcoded values that are now user-configurable to AppState defaults |
| `AppDelegate.swift` | Wire new settings, register both keybinds |
| `Utilities/AudioDeviceEnumerator.swift` | **New file** — CoreAudio device enumeration |

### 7. Menu Bar Dropdown — Visual Refresh

Current menu bar dropdown is bare-bones: a single status label, two dividers, Settings link, Quit. Needs personality.

**Redesigned layout:**

```
┌──────────────────────────────────┐
│  🎙  TeleTalk              Ready │
│  ─────────────────────────────── │
│                                  │
│  ⌃⇧Space  Hold to Talk          │
│  ⌃⇧L      Toggle                │
│                                  │
│  ─────────────────────────────── │
│  Model: Parakeet TDT v2         │
│  Input: MacBook Pro Microphone   │
│  ─────────────────────────────── │
│  Settings...              ⌘,     │
│  Quit TeleTalk            ⌘Q     │
└──────────────────────────────────┘
```

**Improvements:**
- Show app name + colored status dot (green=ready, orange=warning, red=error, pulsing blue=listening)
- Display both active keybinds with their shortcuts so users don't forget them
- Show active model name and input device as context — no clicking into settings just to check
- Use `.foregroundStyle` tints: green for ready, orange for permissions issues, red for errors, blue for recording states
- Listening state: show "Listening..." with animated mic icon inline

### 8. Settings UI — Visual Polish

The current settings look like raw `Form` dumps. Apply consistent visual treatment across all tabs:

**General approach:**
- Use grouped `Form` style (`.formStyle(.grouped)`) for macOS-native grouped appearance
- Section headers with subtle color accents — e.g. tinted SF Symbols next to section titles
- Consistent spacing and alignment across all tabs
- Keybind recorders: show current binding in a styled capsule/chip, not just raw text
- Model cards: rounded rect cards with subtle background, not flat list rows
- Permission badges: larger, with colored background circles instead of just tinted icons
- Status indicators: use filled circles with glow/shadow for active states
- Disabled controls: proper `.disabled()` styling with explanation text

**Color palette:**
- Primary accent: system blue (interactive elements)
- Success: green (permissions granted, model ready)
- Warning: orange (permissions needed)
- Error: red (failures)
- Recording: blue with pulse animation
- Neutral: `.secondary` for labels and descriptions

**Specific components:**
- Model cards in Models tab: `RoundedRectangle` with `.background(.quaternary)`, model icon, name, description, size, status badge, action button
- Hotkey rows: icon + label + styled recorder + enable toggle, all in a clean row
- Audio device picker: show device icon (built-in mic vs USB vs Bluetooth icon based on transport type)
- Permission rows: larger format with icon circle + title + description + status + action

## Out of Scope

- Silence detection / VAD auto-stop
- Language selection UI (model choice implicitly determines language support)
- Streaming transcription
- Sound feedback on record start/stop
- Auto-update mechanism
- Qwen3 ASR or other non-Parakeet models (future ticket)

## Risk

- CoreAudio device enumeration is C-heavy API — needs careful bridging to Swift
- FluidAudio `AsrModels.downloadAndLoad` manages its own cache; deleting files requires knowing the exact cache structure
- Switching models at runtime requires reinitializing `TranscriptionEngine` — must handle mid-recording edge case (disable switch while recording)
