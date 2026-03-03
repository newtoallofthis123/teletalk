# CLAUDE.md

## Project

TeleTalk is a macOS menu bar app for offline voice dictation, targeting Apple Silicon Macs on macOS 14+. It uses NVIDIA's Parakeet TDT model via FluidAudio for 100% local speech-to-text.

## Build Commands

```bash
just build            # Debug build (xcodebuild)
just build-release    # Release build with ad-hoc signing
just install          # Build release + copy to /Applications
just clean            # Clean build artifacts
just format           # Auto-format with swiftformat
just lint             # Lint with swiftlint
just format-check     # CI format check (no writes)
just lint-check       # CI lint check
just open             # Open in Xcode
```

No test suite exists. CI runs `just lint-check` and `just format-check` only.

## Architecture

**Entry point:** `TeletalkApp.swift` → MenuBar scene + Settings window.

**AppDelegate** orchestrates the full pipeline: permissions → model loading → hotkey registration → recording → transcription → text insertion.

**AppState** (`@Observable`, `@MainActor`) is the central state container. All UI state and UserDefaults-backed settings live here.

### Module layout (`Teletalk/`)

- **Audio/** — `AudioRecorder`: AVAudioEngine capture, 16kHz mono Float32 PCM, real-time RMS levels
- **Input/** — `HotkeyManager`: global hotkeys via KeyboardShortcuts (toggle + hold-to-talk modes); `TextInserter`: inserts text via Accessibility API with clipboard-paste fallback
- **Models/** — `TranscriptionEngine`: wraps FluidAudio's AsrManager; `ModelManager`: downloads/switches Parakeet models; `PersonalDictionary`: user vocabulary with aliases for boosting; `TranscriptionHistory`: persisted transcription log
- **UI/** — `MenuBarView`, `SettingsView` (7 tabs), `OverlayView`/`OverlayWindow` (floating recording status + waveform), `SetupView` (first-run wizard)
- **Utilities/** — `Constants`, `Permissions` (mic + accessibility), `AudioDeviceEnumerator`, `SoundEffect`

### Data flow

Hotkey press → AudioRecorder starts → user releases → AudioRecorder returns samples → TranscriptionEngine.transcribe() → TextInserter inserts at cursor → entry added to TranscriptionHistory → overlay dismisses.

### Key dependencies (SPM)

- **FluidAudio** (main branch) — ASR engine wrapping Parakeet TDT + CTC models
- **KeyboardShortcuts** 2.4.0 — global hotkey registration
- **LaunchAtLogin-Modern** — launch at login

## Code Conventions

- Modern Swift concurrency: async/await, `@MainActor` isolation on all managers and state
- `@Observable` macro (not ObservableObject)
- Managers are MainActor-isolated singletons passed via closures/environment
- Persistence: UserDefaults for settings, JSON files in Application Support for dictionary/history
- SwiftFormat: 4-space indent, 120 char line width, `redundantSelf` and `redundantReturn` disabled
- SwiftLint: line length warning at 130, trailing_comma allowed
