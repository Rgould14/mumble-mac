# OpenFlow

A native Swift macOS voice-dictation app modeled on [Wispr Flow](https://wisprflow.ai): speak into any app, release a key, and polished text appears where your cursor is.

## How to use

| Action | Gesture |
|---|---|
| Push-to-talk | **Hold fn**, speak, release to insert |
| Hands-free | **fn + Space** or **double-tap fn** to start; press again (or tap fn / click the red stop button) to finish |
| Cancel | **Esc** |
| Paste last transcript | **⌘⌃V** |

While dictating, a floating **Flow Bar** pill appears at the bottom-center of the screen with live waveform bars; it switches to a processing spinner while your speech is finalized, then the text is pasted into the app you were in.

Transcription uses Apple's on-device/server Speech framework (no API keys). Text is auto-polished: punctuation and capitalization, filler-word removal (um, uh…), personal-dictionary corrections, and spoken snippet expansion.

## Flow Hub

Click the waveform icon in the menu bar → **Open Flow Hub** for:

- **Home** — stats (words dictated, average WPM, day streak) and recent activity
- **History** — searchable transcript log with copy buttons
- **Dictionary** — teach it names/jargon, and map misheard phrases to the right word
- **Snippets** — say a trigger phrase alone (e.g. "insert meeting link") to insert canned text
- **Settings** — activation key/gesture, locale, on-device-only mode, polish options, sounds, permissions

## Build & run

Requires macOS 14+ and Swift 6 command-line tools (no Xcode needed):

```bash
./build-app.sh          # builds release + assembles dist/OpenFlow.app
open dist/OpenFlow.app
```

First launch walks you through three permissions:

1. **Microphone** — capture your voice
2. **Speech Recognition** — transcription
3. **Accessibility** — global hotkeys + inserting text into other apps

> **Important:** set System Settings → Keyboard → *"Press 🌐 key to"* = **Do Nothing**, otherwise macOS grabs the fn key before OpenFlow sees it. If you use a non-Apple keyboard, turn off "Use fn key" in Settings to use **Ctrl+Option** hold instead.

Because the app is ad-hoc signed, macOS resets privacy permissions if the binary changes — re-grant after rebuilding.

## Code map

- `Sources/OpenFlow/main.swift` — app entry, menu bar item, windows
- `HotkeyMonitor.swift` — global fn / Ctrl+Opt / Esc / ⌘⌃V handling
- `DictationController.swift` — session state machine
- `SpeechTranscriber.swift` — AVAudioEngine → SFSpeechRecognizer streaming
- `TextPolisher.swift` — filler removal, dictionary, snippets, cleanup
- `TextInserter.swift` — clipboard-preserving Cmd+V injection
- `FlowBarPanel.swift` — floating waveform pill (NSPanel)
- `HubViews.swift`, `Onboarding.swift` — Flow Hub UI and setup flow
- `Stores.swift` — JSON persistence in `~/Library/Application Support/OpenFlow/`
