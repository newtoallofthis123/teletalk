<p align="center">
  <img src="assets/icon.png" width="200" alt="TeleTalk icon">
</p>

# TeleTalk

Local, privacy-first dictation for macOS. Hold a hotkey, speak, release — transcribed text appears at your cursor. Fully offline, no subscriptions, no cloud.

## Features

- **100% offline** — audio never leaves your device
- **Apple Neural Engine** — near-zero battery impact via ANE inference
- **Hold-to-talk & toggle mode** — configurable hotkeys
- **System-wide** — works in any text field via Accessibility API
- **Fast** — powered by NVIDIA Parakeet TDT 0.6B via [FluidAudio](https://github.com/FluidInference/FluidAudio)

## Requirements

- macOS 14.0+ (Sonoma)
- Apple Silicon (M1 or later)
- Microphone, Accessibility, and Input Monitoring permissions

## Install

```bash
git clone https://github.com/newtoallofthis123/teletalk.git
cd teletalk
./install.sh
```

The installer builds from source, lets you choose between ad-hoc signing (no Apple account) or signing with your Developer ID, and copies the app to `/Applications`.

**Manual build** (if you prefer Xcode):

```bash
open Teletalk.xcodeproj
# Build & Run with Cmd+R
```

Or from the command line:

```bash
xcodebuild -project Teletalk.xcodeproj -scheme Teletalk -configuration Release -derivedDataPath build
cp -r build/Build/Products/Release/Teletalk.app /Applications/
```

The transcription model (~600 MB) downloads automatically on first launch.

## How It Works

TeleTalk is a menu bar app built with Swift and SwiftUI. The pipeline:

1. **Hotkey** — global shortcut via CGEvent tap starts/stops recording
2. **Audio capture** — AVAudioEngine records mic input to a PCM buffer
3. **Transcription** — FluidAudio runs Parakeet TDT on the Apple Neural Engine
4. **Text insertion** — result is inserted at cursor via the Accessibility API (with clipboard paste as fallback)

A small floating overlay shows recording/transcription status.

## License

[MIT](LICENSE)
