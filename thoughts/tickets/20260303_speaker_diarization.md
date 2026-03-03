# Speaker Diarization via FluidAudio Pyannote Pipeline

**Created**: 2026-03-03
**Status**: Draft

---

## Problem Statement

TeleTalk currently transcribes all audio as a single undifferentiated stream of text. When multiple people speak during a recording — meetings, interviews, conversations — there is no way to distinguish who said what. Adding speaker diarization would label each segment of speech with a speaker identity, producing attributed transcriptions like "Speaker 1: ... Speaker 2: ..." without adding any new dependencies.

---

## User Story

**As a** TeleTalk user recording multi-speaker audio
**I want** the transcription to identify and label different speakers
**So that** I can distinguish who said what in meetings, interviews, and conversations

---

## Requirements

### Must Have

1. **DiarizationEngine** — new manager wrapping FluidAudio's `OfflineDiarizerManager`, handling model download and preparation
2. **Model download** — extend `ModelManager` to fetch pyannote_segmentation + wespeaker_v2 CoreML models from `FluidInference/speaker-diarization-coreml` on HuggingFace
3. **Pipeline integration** — run diarization on completed audio buffer, align speaker segments with Parakeet ASR word timestamps, produce speaker-attributed transcript
4. **Settings toggle** — enable/disable diarization (off by default), accessible from SettingsView
5. **Speaker-labeled output** — `TextInserter` formats attributed text with speaker labels before insertion
6. **History storage** — `TranscriptionHistory` persists speaker attribution metadata per entry
7. **Lazy loading** — diarization models only downloaded/prepared when the feature is enabled

### Nice to Have

- Run diarization and ASR in parallel on the same audio buffer to minimize total latency
- Speaker count indicator in OverlayView after transcription completes
- Configurable speaker label format (Speaker 1/2/3, custom names)
- Advanced tuning: clustering threshold (default 0.7), min speech duration, min silence gap
- Streaming diarization via `DiarizerManager` for a future continuous listening mode

### Won't Have (out of scope)

- Real-time streaming diarization (future work if continuous listening is added)
- Speaker identification (recognizing *known* speakers by name automatically)
- Sortformer pipeline (4-speaker hard limit, less mature)
- Any new SPM dependencies (SpeakerKit, pyannote-rs, etc.)

---

## Acceptance Criteria

- [ ] Diarization toggle exists in Settings, defaults to off
- [ ] Enabling diarization triggers model download (~50-100 MB) with progress indication
- [ ] Single-speaker recordings transcribe identically to current behavior (no regression)
- [ ] Multi-speaker recordings produce speaker-labeled output (e.g., "Speaker 1: ... \n Speaker 2: ...")
- [ ] Speaker labels are consistent within a single recording (same speaker gets the same label throughout)
- [ ] Diarization adds less than 1 second of latency for a 30-second clip on M1
- [ ] TranscriptionHistory entries include speaker attribution when diarization is enabled
- [ ] Disabling diarization skips all diarization processing entirely (no performance cost)
- [ ] Models are not downloaded until the user enables diarization

---

## Technical Notes

### Chosen Approach

FluidAudio's Pyannote CoreML pipeline. Zero new dependencies — FluidAudio is already our ASR engine.

**Models**: `pyannote_segmentation.mlmodelc` + `wespeaker_v2.mlmodelc` from [FluidInference/speaker-diarization-coreml](https://huggingface.co/FluidInference/speaker-diarization-coreml). Run FP16 on Apple Neural Engine.

**Performance**: RTF 0.017 on M1 (60x real-time). ~22% DER. Unlimited speaker count.

**Input**: 16kHz mono Float32 — identical to what `AudioRecorder` already produces for Parakeet. No format conversion needed.

### API Surface

```swift
// Offline batch (recommended for push-to-talk)
let manager = OfflineDiarizerManager(config: OfflineDiarizerConfig())
try await manager.prepareModels()
let result = try await manager.process(audio: samples)

// Streaming (future, for continuous listening)
let manager = DiarizerManager(config: DiarizerConfig())
// clusteringThreshold: 0.5-0.9, default 0.7
// minSpeechDuration, minSilenceGap tunable
```

### Pipeline Integration

```
Current:  Hotkey release → samples → TranscriptionEngine.transcribe() → TextInserter → History
Proposed: Hotkey release → samples → DiarizationEngine.process() → TranscriptionEngine.transcribe()
          → align words to speaker segments by timestamp → TextInserter (attributed) → History
```

Diarization and ASR can potentially run in parallel since both accept the same audio buffer independently.

### Components to Create/Modify

| Component | Change | Reason |
|---|---|---|
| `Models/DiarizationEngine` | **New** | Wraps `OfflineDiarizerManager`, model lifecycle |
| `Models/ModelManager` | Extend | Download diarization models alongside Parakeet |
| `AppDelegate` | Modify | Orchestrate diarization step in pipeline |
| `AppState` | Modify | Diarization toggle, speaker label prefs |
| `Models/TranscriptionEngine` | Modify | Accept diarization segments, align with ASR timestamps |
| `Input/TextInserter` | Modify | Format speaker-attributed text |
| `Models/TranscriptionHistory` | Modify | Store speaker attribution metadata |
| `UI/SettingsView` | Modify | Diarization settings section |
| `UI/OverlayView` | Modify (optional) | Show speaker count |

### Alternatives Considered & Rejected

| Alternative | Why Rejected |
|---|---|
| FluidAudio Sortformer | Hard 4-speaker limit, less mature |
| SpeakerKit (Argmax) | Adds new SPM dependency; 10 MB models + better DER (17%) but not worth the coupling |
| Apple Speech framework | No diarization API exists at any OS version |
| NVIDIA NeMo directly | GPU/CUDA only, no Apple Silicon path |
| pyannote-audio (Python) | Broken on Mac since v3.0.1 |

---

## Resolved Questions

1. **Speaker label format** — `Speaker 1:`, `Speaker 2:`, etc. as line prefixes.
2. **Single-speaker recordings** — suppress labels entirely; output matches current behavior.
3. **Overlapping speech** — use standard temporal overlap alignment: each ASR word/segment is assigned to the diarization speaker with the longest time intersection. In simultaneous speech, the dominant speaker wins. This is the established approach (used by WhisperX, whisper-diarization, etc.) and is acceptable for push-to-talk where true crosstalk is rare.
4. **Model download UX** — opt-in only. Models are downloaded exclusively when the user enables diarization from Settings, with download progress clearly shown in the UI. Not part of the first-run SetupView wizard.
