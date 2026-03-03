# AI-Enhanced Dictation via Apple Intelligence

**Created**: 2026-03-03
**Status**: Draft

---

## Problem Statement

TeleTalk's speech-to-text output is raw transcription — it includes filler words (um, uh, like), lacks proper punctuation, and has no capitalization or formatting. Users who want polished text must manually clean up every transcription.

macOS 26 ships an on-device ~3B parameter LLM via the FoundationModels framework. We can use this to add an opt-in post-processing step that cleans up transcription output before inserting it — entirely local, no network calls, no API keys.

---

## User Story

**As a** TeleTalk user on macOS 26 with Apple Intelligence enabled
**I want** to optionally run my transcriptions through on-device AI for cleanup
**So that** I get polished, punctuated, filler-free text without manual editing

---

## Requirements

### Must Have

1. **Opt-in activation via dedicated hotkey** — A new hotkey (separate from existing dictation hotkeys) that triggers "AI-enhanced dictation." The existing hotkeys continue to work as plain dictation. The user chooses plain vs. enhanced per-utterance at the moment they press the key.
2. **macOS 26 availability gate** — Feature is fully conditional behind `@available(macOS 26, *)` and a runtime `SystemLanguageModel.default.isAvailable` check. If the device is ineligible or Apple Intelligence is not enabled, the feature and its settings are completely hidden from the UI.
3. **Editable system prompt** — Ship a default system prompt (filler word removal, punctuation, capitalization). The user can edit or fully replace this prompt from Settings. Stored in UserDefaults. One prompt — no persona/preset system.
4. **Token overflow passthrough** — If the transcription exceeds what the 4,096-token context window can handle, skip AI processing and insert raw text as-is. No error shown.
5. **Graceful error fallback** — If FoundationModels throws for any reason (guardrail rejection, model not ready, token overflow, unexpected error), fall back to raw transcription text. Never block the user's workflow. No pre-estimation of token count — just catch the error.
6. **Settings UI** — New section in Settings for AI enhancement: enable toggle (hidden if not eligible), system prompt text editor with reset-to-default, AI hotkey picker.
7. **Overlay state indication** — Update the recording overlay to show an "Enhancing..." state while AI post-processing is running, so the user knows why insertion is delayed.

### Won't Have (out of scope)

- Multiple personas or preset prompt library
- Cloud/API-based AI providers (OpenRouter, Claude, etc.)
- Streaming partial AI output to the user
- Per-app or per-context prompt switching
- Prompt chaining or multi-step processing

---

## Acceptance Criteria

- [ ] AI-enhanced dictation hotkey can be configured independently from the existing dictation hotkey (toggle mode only, no hold-to-talk)
- [ ] Pressing the AI hotkey records, transcribes, runs through FoundationModels, and inserts cleaned text
- [ ] Pressing the regular hotkey records, transcribes, and inserts raw text (unchanged behavior)
- [ ] On macOS < 26 or with Apple Intelligence unavailable, AI settings section is not visible
- [ ] Default system prompt removes filler words and fixes punctuation/capitalization
- [ ] User can edit the system prompt in Settings and changes persist across app restarts
- [ ] User can reset the system prompt to the shipped default
- [ ] Long transcriptions that would exceed the token limit are inserted as raw text without error
- [ ] If FoundationModels throws, raw text is inserted and user is not blocked
- [ ] Overlay shows "Enhancing..." or similar indicator during AI processing
- [ ] Feature is fully disabled by default — no AI processing occurs until user enables it and configures the hotkey

---

## Technical Notes

### Framework

```swift
import FoundationModels
```

System framework — no SPM dependency. No entitlement needed (app runs unsandboxed).

### Key API

```swift
// Availability check
SystemLanguageModel.default.isAvailable
SystemLanguageModel.default.availability // .available, .unavailable(.appleIntelligenceNotEnabled), etc.

// Inference
let session = LanguageModelSession()
let options = GenerationOptions(sampling: .greedy, temperature: 0.1)
let response = try await session.respond(to: prompt, options: options)
return response.content
```

### Reference Implementation

[FlowStay](https://github.com/maketheproduct/flowstay) — same FluidAudio-based architecture. See `AppleIntelligenceHelper.swift` (~30 lines) and `PersonasEngine.swift` for the proven pattern.

### Module Layout

| File | Responsibility |
|---|---|
| `AI/AIPostProcessor.swift` | Wraps FoundationModels: availability check, session management, prompt assembly, inference, error fallback. Guarded behind `@available(macOS 26, *)`. |
| `Input/HotkeyManager.swift` | Add second hotkey slot for AI-enhanced dictation |
| `TeletalkApp.swift` / `AppDelegate.swift` | Branch in transcription callback: AI hotkey → post-process → insert; regular hotkey → insert directly |
| `AppState.swift` | New settings: `aiEnhancementEnabled` (Bool), `aiSystemPrompt` (String), AI hotkey binding |
| `UI/SettingsView.swift` | New AI enhancement section: toggle, prompt editor, hotkey picker |
| `UI/OverlayView.swift` | "Enhancing..." state during AI processing |

### Default System Prompt

```
Remove filler words (um, uh, like, you know). Fix punctuation and capitalization. Output only the corrected text — no commentary, no quotation marks, no acknowledgments.
```

### Constraints

- **macOS 26+ only** — all FoundationModels code behind `@available(macOS 26, *)`
- **4,096 token context** — input + output combined; need to estimate token count and bail if too long
- **Guardrails always on** — Apple content filters cannot be disabled; edge-case rejections possible on sensitive dictated content
- **Latency** — on-device inference adds delay; acceptable because user explicitly opts in per-utterance

---

## Open Questions

None — all resolved:
- Token overflow: no pre-estimation; just catch the FoundationModels error and fall back to raw text
- Overlay: reuse existing waveform animation style for the "Enhancing..." state
- AI hotkey mode: toggle only (no hold-to-talk for AI enhancement)
