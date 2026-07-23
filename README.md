# Mumble

Native macOS voice dictation with an AI polish layer — speak into any app and polished text lands wherever your cursor is. Inspired by Wispr Flow, built in Swift/SwiftUI with no Xcode project required.

**Highlights**

- **Push-to-talk & hands-free** dictation with a floating recording HUD (live waveform, live transcript preview)
- **Two-stage pipeline**: Apple speech recognition → Claude rewrites the transcript (fixes misheard words from context, punctuation, filler removal, tone adapted to the target app)
- **Learns from you**: edit a dictation after it lands and Mumble remembers the correction — repeat corrections apply automatically and steer future cleanups
- **Prompt Mode**: ramble your intent, get back a prompt engineered for Claude Code / your IDE / a chat assistant, following Anthropic's prompt-engineering best practices
- **Insights dashboard**: words dictated, average WPM, fixes made, per-app usage, streak heatmap
- Continuous listening — pauses become sentence boundaries, nothing gets rewritten or lost
- Bluetooth-friendly: captures from the built-in mic so your headphones stay in high-quality audio while music plays

## Install (5 minutes)

**Downloading the release build?** Grab the zip from [Releases](https://github.com/Rgould14/mumble-mac/releases). macOS blocks the first open (the build isn't Apple-notarized): click Done, then System Settings → Privacy & Security → "Open Anyway" — or run `xattr -d com.apple.quarantine /Applications/Mumble.app`. Then continue from the permissions list below.

**Building from source?** Requires **macOS 14+** and the Swift command-line tools (`xcode-select --install` — no Xcode needed).

```bash
git clone https://github.com/Rgould14/mumble-mac.git
cd mumble-mac
./setup-signing.sh      # once per machine: creates a stable signing identity
./build-app.sh          # builds dist/Mumble.app
open dist/Mumble.app
```

Then grant the permissions (one time — the stable signing identity keeps them across rebuilds):

1. **Microphone** and **Speech Recognition** — allow the prompts on first dictation
2. **Accessibility** — System Settings → Privacy & Security → Accessibility → add `dist/Mumble.app`
3. **Input Monitoring** — same pane group; needed for the global fn hotkey
4. Turn on **macOS Dictation** (System Settings → Keyboard → Dictation) — Apple's speech engine requires it
5. Set System Settings → Keyboard → *"Press 🌐 key to"* = **Do Nothing** so macOS doesn't intercept fn

### API key (for AI cleanup + Prompt Mode)

Set an Anthropic API key in **Mumble Hub → Settings → AI cleanup** (or export `ANTHROPIC_API_KEY`). Pick the model there — Opus (most accurate), Sonnet (balanced), Haiku (fastest). Without a key, Mumble still works with rule-based cleanup, fully offline.

## Using Mumble

| Action | Gesture |
|---|---|
| Push-to-talk | **Hold fn**, speak, release to insert |
| Hands-free | **fn + Space** (or double-tap fn); press again / tap fn / stop button to finish |
| **Prompt Mode** | **fn + P** — ramble intent, an engineered prompt is inserted |
| Cancel | **Esc** |
| Paste last transcript | **⌘⌃V** |

Where the text goes: if you're focused in a text field it's inserted directly (your clipboard is preserved); if nothing editable is focused it's put on the clipboard with a HUD notice. Everything is also saved to History.

**Prompt Mode** infers the target from the app you're in — terminal → coding-agent prompt (full spec, goals + verification criteria), IDE → short imperative inline prompt, browser/chat → context-then-question chat prompt. Fallback target is configurable in Settings.

## Mumble Hub

Menu bar icon → **Open Mumble Hub**:

- **Home** — insights dashboard (words, WPM, streak, fixes, app usage, heatmap) + recent activity
- **History** — searchable transcript log
- **Dictionary** — names/jargon, and misheard-phrase → correct-word mappings
- **Snippets** — say a trigger phrase alone to insert canned text
- **Learning** — everything Mumble has learned from your edits, with per-item delete
- **Settings** — activation, locale, mic preference, AI cleanup, Prompt Mode target

## Architecture

```
fn hotkey ─▶ DictationController (state machine) ─▶ HUD overlay
                    │
       AVCaptureSession (built-in mic, by device ID)
                    ▼
       SFSpeechRecognizer — segmented; pauses freeze text, never rewrite
                    ▼
       LLMCleanup (Claude) ─ or ─ PromptRewriter (Prompt Mode)
                    ▼
       Post-process: snippets · dictionary · learned corrections
                    ▼
       FocusDetector ─▶ paste into field / clipboard fallback
                    ▼
       EditWatcher diffs your edits ─▶ corrections store ─▶ feeds back ↑
```

Everything persists as JSON in `~/Library/Application Support/Mumble/`. A debug log lives there too (`debug.log`) — check it first if something misbehaves.

## Code map

- `Sources/Mumble/main.swift` — app entry, menu bar, windows
- `DictationController.swift` — session state machine (PTT, hands-free, prompt mode)
- `HotkeyMonitor.swift` — global fn / fn+Space / fn+P / Esc / ⌘⌃V
- `SpeechTranscriber.swift` — AVCaptureSession → segmented SFSpeechRecognizer
- `LLMCleanup.swift` / `PromptRewriter.swift` — Claude cleanup + prompt engineering
- `TextPolisher.swift` / `Learning.swift` — local fixes, edit-diff learning
- `FocusDetector.swift` / `TextInserter.swift` — where text goes, and how
- `FlowBarPanel.swift` — recording HUD (waveform, pills)
- `HubViews.swift` / `InsightsView.swift` / `Onboarding.swift` — Hub UI
- `Theme.swift` — Mumble design system tokens
- `docs/BACKLOG.md` — roadmap
