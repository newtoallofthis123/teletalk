# TeleTalk — Initial Research

## What We're Building

A local, privacy-first macOS speech-to-text tool that replicates the WisprFlow experience — hold a hotkey, speak, release, and polished text appears at your cursor. Fully offline. No subscription. No cloud.

---

## WisprFlow: The Reference Experience

Source: [wisprflow.ai](https://wisprflow.ai/) | [Cult of Mac Review](https://www.cultofmac.com/reviews/wispr-flow-mac-speech-to-text-app-review) | [Zack Proser Review](https://zackproser.com/blog/wisprflow-review)

### How It Works
1. Hold hotkey (Fn on Mac) → small overlay appears showing "recording"
2. Speak naturally — ramble, use filler words, whatever
3. Release hotkey → 1-2 seconds later, polished text appears at cursor
4. Works **system-wide** in any text field (Slack, VS Code, browser, etc.)

### Features
- **AI Auto-Edits**: Strips filler words ("um", "uh"), adds punctuation, polishes grammar
- **Tone Adaptation**: Adjusts formality based on which app you're in
- **Personal Dictionary**: Learns your jargon, acronyms, brand names
- **Snippet Library**: Voice shortcuts that expand to predefined text
- **Whisper Mode**: Recognizes quietly spoken words for library/office use
- **100+ languages** with auto-detection
- ~175-220 WPM (vs 45-90 WPM typing)

### Downsides (Our Opportunity)
- **Cloud-based** — audio sent to their servers (privacy concern)
- **$8/month subscription**
- Closed source
- Requires internet connection

---

## Transcription Models: The Landscape

### OpenAI Whisper Family

| Model | Params | WER | Speed | Languages |
|-------|--------|-----|-------|-----------|
| Whisper large-v3 | 1.55B | ~9.9% | Baseline | 99+ |
| Whisper large-v3-turbo | 809M | ~10.5% | 6x faster (reduced decoder layers 32→4) | 99+ |
| distil-large-v3 | ~750M | Within 1% of large-v3 | 6x faster | English-focused |
| Whisper small.en | ~244M | Higher WER | Very fast | English only |

**Apple Silicon runtimes:**
- [whisper.cpp](https://github.com/ggerganov/whisper.cpp) — C/C++, CoreML support, most battle-tested. Embeddable in Swift apps.
- [mlx-whisper](https://pypi.org/project/mlx-whisper/) — Python, MLX-native. ~2x faster than whisper.cpp.
- [lightning-whisper-mlx](https://github.com/mustafaaljadery/lightning-whisper-mlx) — Python, claims 10x faster than whisper.cpp via batched decoding + distilled models.

Sources: [Modal STT comparison](https://modal.com/blog/open-source-stt) | [Northflank 2026 benchmarks](https://northflank.com/blog/best-open-source-speech-to-text-stt-model-in-2026-benchmarks)

### NVIDIA Parakeet Family (The Winner)

| Model | Params | WER | Speed (RTFx) | Languages |
|-------|--------|-----|--------------|-----------|
| **Parakeet TDT 0.6B v2** | **600M** | **6.05%** | **3380x** | English only |
| **Parakeet TDT 0.6B v3** | **600M** | **9.7%** | **3332x** | 25 languages |
| Parakeet TDT 1.1B | 1.1B | <7.0% | 64% faster than RNNT | English |

Key insight: Parakeet v2 is **half the size** of Whisper large-v3 with **significantly lower WER** for English. At 600M params, it's more resource-efficient and faster.

**Apple Silicon runtimes:**
- [FluidAudio](https://github.com/FluidInference/FluidAudio) — **Swift SDK**, MIT/Apache 2.0. Runs Parakeet on **Apple Neural Engine (ANE)** directly. ~190x RTF on M4 Pro (1 hour audio in ~19 seconds). Leaves CPU/GPU free. Near-zero battery impact.
- [parakeet-mlx](https://github.com/senstella/parakeet-mlx) — MLX implementation for Apple Silicon
- [CoreML converted models](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml) — Ready-to-use on HuggingFace
- [parakeet.cpp](https://github.com/jason-ni/parakeet.cpp) — C++ implementation (like whisper.cpp for Parakeet)

Sources: [NVIDIA Parakeet v2 vs Whisper](https://medium.com/data-science-in-your-pocket/nvidia-parakeet-v2-vs-openai-whisper-which-is-the-best-asr-ai-model-5912cb778dcf) | [NVIDIA Speech AI Blog](https://developer.nvidia.com/blog/nvidia-speech-ai-models-deliver-industry-leading-accuracy-and-performance/) | [Parakeet TDT v3 HuggingFace](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3)

### Why Parakeet + FluidAudio Over Whisper.cpp

| Dimension | FluidAudio + Parakeet | whisper.cpp |
|-----------|----------------------|-------------|
| Language | Pure Swift | C, needs bridging |
| Inference | Apple Neural Engine (ANE) | CPU/GPU |
| Battery | Near-zero (ANE offload) | Moderate CPU usage |
| English WER | 6.05% (v2) | ~10% (large-v3) |
| Model size | 600M params | 1.55B (large-v3) |
| Latency (10s clip) | ~50ms | ~200-500ms |
| License | MIT / Apache 2.0 | MIT |
| Multilingual | 25 langs (v3) | 99+ langs |

Whisper.cpp remains valuable as a **fallback for unsupported languages**.

---

## Existing Open Source Prior Art

### VoiceInk (Primary Reference)
- **Repo**: [github.com/Beingpax/VoiceInk](https://github.com/Beingpax/VoiceInk)
- **Stack**: Swift (99.5%), whisper.cpp + FluidAudio (Parakeet), SwiftUI
- **Features**: Push-to-talk, context-aware, personal dictionary, 100% offline
- **Dependencies**: `KeyboardShortcuts`, `SelectedTextKit`, `LaunchAtLogin`, `MediaRemoteAdapter`, `Sparkle`
- **Requires**: macOS 14.4+, Apple Silicon
- Closest to what we want. Validates the FluidAudio + Parakeet path.

### Others
- [OpenWhispr](https://openwhispr.com/) — Cross-platform, open source, Whisper + Parakeet
- [Whispering](https://github.com/braden-w/whispering) — Electron-based, cross-platform
- [SuperWhisper](https://superwhisper.com/) — Paid Mac app, local Whisper

---

## macOS Integration: How Text Insertion Works

Source: [Swift text insertion guide](https://levelup.gitconnected.com/swift-macos-insert-text-to-other-active-applications-two-ways-9e2d712ae293)

### Two Approaches

**1. Accessibility API (Primary)**
- Use `AXUIElementCreateSystemWide()` → get `kAXFocusedUIElementAttribute` → set `kAXValueAttribute`
- Direct text insertion into the focused text field
- Requires: Accessibility permission in System Settings

**2. Clipboard + Simulated Paste (Fallback)**
- Write text to `NSPasteboard`
- Simulate `Cmd+V` via `CGEvent` (keyDown + keyUp with `.maskCommand`)
- More universally compatible but overwrites clipboard

### Required Permissions
- **Microphone** (`NSMicrophoneUsageDescription`)
- **Accessibility** (System Settings → Privacy → Accessibility) — for text insertion + global hotkey
- **Input Monitoring** — for global hotkey capture

### Distribution
- **Cannot use App Store** — accessibility + input monitoring permissions require disabling App Sandbox
- Distribute via **DMG / direct download** using Developer ID signing
- Updates via Sparkle framework

---

## Proposed Architecture

```
TeleTalk (Swift, macOS menu bar app)
│
├── Hotkey Listener (CGEvent tap)
│   └── Hold-to-talk or toggle mode
│
├── Audio Capture (AVAudioEngine)
│   └── Mic input → PCM buffer
│
├── Transcription Engine
│   ├── Primary: FluidAudio + Parakeet TDT v2 (ANE, English)
│   ├── Multilingual: Parakeet TDT v3 (25 languages)
│   └── Fallback: whisper.cpp (99+ languages)
│
├── Text Processing (optional)
│   └── Filler word removal, punctuation, formatting
│
├── Overlay UI (NSPanel, floating)
│   └── Small pill/badge: "Listening..." → "Transcribing..." → dismiss
│
└── Text Inserter
    ├── Primary: AXUIElement accessibility API
    └── Fallback: NSPasteboard + CGEvent Cmd+V
```

## UX Flow

1. User presses hotkey (e.g., `Fn` or `Ctrl+Shift+Space`)
2. Small floating pill appears near cursor or bottom-center: recording indicator with subtle animation
3. Audio streams into buffer via AVAudioEngine
4. User releases hotkey (or presses again for toggle mode)
5. Pill changes to "Transcribing..." briefly
6. Parakeet TDT processes the buffer (~50ms for short utterances on M-series)
7. Text is inserted at cursor via Accessibility API
8. Pill disappears

---

## Tech Stack

| Layer | Choice | Rationale |
|-------|--------|-----------|
| Language | Swift | Native macOS, no runtime overhead |
| UI Framework | SwiftUI + AppKit (NSPanel) | Modern UI with low-level floating window control |
| Transcription | FluidAudio + Parakeet TDT | Swift-native, ANE inference, best English accuracy |
| Fallback STT | whisper.cpp | Broad language support, battle-tested |
| Audio | AVAudioEngine | Native, low-latency mic capture |
| Hotkey | CGEvent tap | Most reliable global hotkey mechanism |
| Text Insertion | AXUIElement + CGEvent | System-wide text insertion |
| Distribution | DMG + Developer ID | Can't App Store (needs accessibility) |
| Updates | Sparkle | Standard macOS update framework |

---

## Differentiators from WisprFlow

1. **Fully local** — no audio leaves the device, ever
2. **Free and open source** — no subscription
3. **ANE-powered** — near-zero battery impact via Neural Engine
4. **Dead simple** — one hotkey, one model, it works
5. **Streaming preview** (stretch goal) — show partial transcription as you speak
6. **Context-aware formatting** (stretch goal) — detect code editor vs chat app

---

## Decisions

1. **English-only** — Parakeet TDT 0.6B v2 (6.05% WER, best accuracy)
2. **No AI cleanup in MVP** — raw transcription first. LLM polish pass is a future feature
3. **Both hotkey modes** — hold-to-talk + toggle, user-configurable
4. **Download model on first launch** — keeps app binary small, ~600MB download once
5. **macOS 14.0+ (Sonoma)** — matches FluidAudio requirements
