# Overlay UI Polish & Bug Fix

**Created**: 2026-03-03
**Status**: Draft

---

## Problem Statement

The overlay UI has a bug where the "Listening" text only appears on first use — subsequent recordings show nothing. Beyond the bug, the overlay feels bare-bones: no audio feedback while speaking, generic spinner during transcription, no entrance/exit animations, and a success state that vanishes too quickly to register. The overlay should feel responsive, polished, and give clear visual feedback at every stage.

---

## User Story

**As a** TeleTalk user
**I want** a polished overlay that reacts to my voice and clearly shows each state
**So that** I have confidence the app is hearing me and processing my speech

---

## Requirements

### Must Have

1. **Fix re-show bug** — "Listening" text and icon must display reliably on every recording, not just the first
2. **Audio-reactive waveform** — 3-5 bars during `.listening` state that bounce based on real-time mic input level (RMS from AVAudioEngine tap)
3. **Animated transcribing state** — custom animation (bouncing dots or similar) replacing the plain `ProgressView` spinner
4. **Success animation** — checkmark with scale-in + fade, green accent color, visible for ~600ms (up from 300ms)
5. **Entrance/exit transitions** — slide up + fade in on show, slide down + fade out on hide
6. **State-tinted pill** — subtle background color per state: blue-tint for listening, neutral for transcribing, green-tint for success, red-tint for error
7. **Spring animations** — replace `.easeInOut(0.2)` with spring-based transitions for state changes

### Won't Have (out of scope)

- Frequency-domain waveform visualization (FFT spectrograms)
- User-configurable animation settings
- Overlay resize or drag-to-reposition
- Themeable overlay colors

---

## Acceptance Criteria

- [ ] Recording overlay shows "Listening" text + icon every time, including 2nd, 3rd, nth use
- [ ] Waveform bars visibly react to voice input in real-time during listening
- [ ] Waveform bars are idle/minimal when user is silent
- [ ] Transcribing state shows a custom animation (not system ProgressView)
- [ ] Success state shows an animated green checkmark that holds for ~600ms
- [ ] Overlay slides up + fades in when appearing
- [ ] Overlay slides down + fades out when disappearing
- [ ] Each state has a distinct subtle color tint on the pill background
- [ ] State transitions use spring animations, not linear/ease
- [ ] No performance regression — overlay animations don't affect transcription latency

---

## Technical Notes

### Bug fix (re-show)
- **Root cause**: `NSHostingView` created once in `OverlayWindow.createPanel()`. SwiftUI observation via `@Observable` AppState may not re-trigger after panel `orderOut`/`orderFront` cycles.
- **Fix approach**: Either recreate the hosting view on each `show()`, or force invalidation (e.g. toggle a dummy state, or use `needsDisplay = true` on the hosting view). Test by recording 3+ times in succession.

### Audio levels for waveform
- **AudioRecorder.swift** uses `AVAudioEngine` with an input node tap accumulating `[Float]` samples at 16kHz.
- Add RMS calculation inside the existing tap callback: `sqrt(buffer.map { $0 * $0 }.reduce(0, +) / Float(buffer.count))`
- Publish as an observable property on AudioRecorder or AppState (e.g. `audioLevel: Float`, updated ~15-30 times/sec).
- OverlayView reads `audioLevel` to drive bar heights during `.listening`.

### Key files
| File | Change |
|------|--------|
| `OverlayView.swift` | Waveform bars, state tints, transitions, animations |
| `OverlayWindow.swift` | Fix re-show bug, entrance/exit slide transitions |
| `AudioRecorder.swift` | Expose real-time RMS audio level |
| `AppState.swift` | Add `audioLevel: Float` property |
| `AppDelegate.swift` | Adjust success state hold duration |
| `Constants.swift` | Update timing constants |

---

## Open Questions

- [ ] Should waveform bars use discrete stepped levels or smooth continuous interpolation?
- [ ] Should the entrance slide come from bottom regardless of overlay position (top/bottom/cursor)?
