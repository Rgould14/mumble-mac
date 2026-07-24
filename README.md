# Mumble

Native macOS voice dictation with an AI polish layer — speak into any app and polished text lands wherever your cursor is. Built in Swift/SwiftUI with no Xcode project required.

**Highlights**

- **Push-to-talk & hands-free** dictation with a floating recording HUD (live waveform, live transcript preview)
- **Two-stage pipeline**: Apple speech recognition → Claude rewrites the transcript (fixes misheard words from context, punctuation, filler removal, tone adapted to the target app)
- **Learns from you**: edit a dictation after it lands and Mumble remembers the correction — repeat corrections apply automatically and steer future cleanups
- **Prompt Mode**: ramble your intent, get back a prompt engineered for Claude Code / your IDE / a chat assistant, following Anthropic's prompt-engineering best practices
- **Insights dashboard**: words dictated, average WPM, fixes made, per-app usage, streak heatmap
- Continuous listening — pauses become sentence boundaries, nothing gets rewritten or lost
- Bluetooth-friendly: captures from the built-in mic so your headphones stay in high-quality audio while music plays

## Install

**Requires an Apple Silicon Mac (M1 or newer) on macOS 14+.** Intel Macs aren't supported by the prebuilt download — build from source instead.

### Option A — download the app (easiest)

1. Download **Mumble-v1.0.zip** from [Releases](https://github.com/Rgould14/mumble-mac/releases), unzip it, and drag **Mumble.app** to your Applications folder.
2. **First open is blocked** ("Apple could not verify…") because the build isn't Apple-notarized. Click **Done** (not Move to Bin), then open **System Settings → Privacy & Security**, scroll to the bottom, and click **Open Anyway** next to Mumble → confirm.
   - Terminal shortcut instead: `xattr -d com.apple.quarantine /Applications/Mumble.app`, then open normally.
3. Grant these in **System Settings → Privacy & Security** (add Mumble to each): **Microphone**, **Speech Recognition**, **Accessibility**, **Input Monitoring**. Mic and Speech prompt automatically on your first dictation; Accessibility and Input Monitoring you add manually.
4. Turn on **macOS Dictation** — System Settings → Keyboard → Dictation → **On**. Apple's speech engine requires it.
5. Free the fn key — System Settings → Keyboard → *"Press 🌐 key to"* → **Do Nothing** so macOS doesn't intercept it.
6. Optional: add an Anthropic API key in **Mumble Hub → Settings** for AI cleanup and Prompt Mode (see below).

Then hold **fn**, speak, and release — text appears where your cursor is.

### Option B — build from source

Needs the Swift command-line tools (`xcode-select --install` — no full Xcode required):

```bash
git clone https://github.com/Rgould14/mumble-mac.git
cd mumble-mac
./setup-signing.sh      # once per machine: stable signing identity so permissions persist
./build-app.sh          # builds dist/Mumble.app
open dist/Mumble.app
```

Building locally skips the Gatekeeper block in step 2 above; grant the same permissions (steps 3–5).

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
