import AppKit
import Combine

enum DictationState: Equatable {
    case idle
    case recording(handsFree: Bool)
    case processing
}

/// Central state machine tying hotkeys -> transcriber -> polisher -> inserter.
final class DictationController: ObservableObject {
    static let shared = DictationController()

    @Published var state: DictationState = .idle
    /// Short outcome message shown in the Flow Bar after a session (e.g. copied).
    @Published var notice: String?
    let transcriber = SpeechTranscriber()
    let hotkeys = HotkeyMonitor()

    private var startedAt = Date()
    private var targetApp: NSRunningApplication?
    private var targetIsTextInput = false
    private var sessionTimer: Timer?

    var isDictating: Bool { if case .recording = state { return true }; return false }

    private init() {
        hotkeys.isDictating = { [weak self] in self?.isDictating ?? false }
        hotkeys.settings = { AppState.shared.settings }
        hotkeys.onPushToTalkDown = { [weak self] in self?.pushToTalkDown() }
        hotkeys.onPushToTalkUp = { [weak self] in self?.pushToTalkUp() }
        hotkeys.onHandsFreeToggle = { [weak self] in self?.toggleHandsFree() }
        hotkeys.onCancel = { [weak self] in self?.cancel() }
        hotkeys.onPasteLast = { pasteLastTranscript() }
    }

    func startMonitoring() { hotkeys.start() }

    // MARK: Gestures

    private func pushToTalkDown() {
        Log.line("push-to-talk down (state=\(state))")
        switch state {
        case .recording(handsFree: true):
            stopAndInsert() // tapping the key ends a hands-free session
        case .idle:
            start(handsFree: false)
        default: break
        }
    }

    private func pushToTalkUp() {
        // Ignore releases from the tap that just started/stopped hands-free.
        if case .recording(handsFree: false) = state {
            let held = Date().timeIntervalSince(startedAt)
            if held < 0.25 { cancel() } else { stopAndInsert() }
        }
    }

    func toggleHandsFree() {
        switch state {
        case .idle: start(handsFree: true)
        case .recording: stopAndInsert()
        default: break
        }
    }

    // MARK: Session

    func start(handsFree: Bool) {
        guard case .idle = state else { return }
        let settings = AppState.shared.settings
        targetApp = NSWorkspace.shared.frontmostApplication
        // Decide the destination now, while the user's click focus is intact.
        targetIsTextInput = FocusDetector.focusedElementIsTextInput()
        notice = nil
        do {
            try transcriber.start(locale: Locale(identifier: settings.localeIdentifier),
                                  onDeviceOnly: settings.onDeviceOnly)
        } catch {
            Log.line("start FAILED: \(error.localizedDescription)")
            NSSound.beep()
            let msg = error.localizedDescription.contains("Dictation")
                ? "Turn on macOS Dictation: System Settings → Keyboard → Dictation"
                : error.localizedDescription
            notice = msg
            FlowBarPanel.shared.show()
            FlowBarPanel.shared.hideSoon(after: 3.5)
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 3_500_000_000); self?.notice = nil
            }
            return
        }
        Log.line("recording started (handsFree=\(handsFree))")
        startedAt = Date()
        state = .recording(handsFree: handsFree)
        if settings.playSounds { Sounds.play("Pop") }
        FlowBarPanel.shared.show()

        sessionTimer?.invalidate()
        sessionTimer = Timer.scheduledTimer(withTimeInterval: Double(settings.maxSessionMinutes) * 60,
                                            repeats: false) { [weak self] _ in
            self?.stopAndInsert()
        }
    }

    func stopAndInsert() {
        guard isDictating else { return }
        sessionTimer?.invalidate()
        let duration = Date().timeIntervalSince(startedAt)
        state = .processing
        if AppState.shared.settings.playSounds { Sounds.play("Tink") }
        let appName = targetApp?.localizedName ?? "Unknown"
        transcriber.stop { [weak self] raw in
            guard let self else { return }
            Task { await self.finish(raw: raw, appName: appName, duration: duration) }
        }
    }

    /// Runs stage-2 LLM cleanup (async) with a rule-based fallback, records the
    /// transcript, and pastes it into the target app.
    private func finish(raw: String, appName: String, duration: Double) async {
        let text: String
        do {
            text = try await LLMCleanup.clean(raw, appName: appName, state: AppState.shared)
        } catch {
            text = TextPolisher.polish(raw, state: AppState.shared)
        }
        // Snippet expansion + dictionary + learned corrections apply locally on
        // top of the LLM output.
        let final = LearnedCorrections.apply(
            TextPolisher.postProcess(text, state: AppState.shared),
            state: AppState.shared)

        state = .idle
        guard !final.isEmpty else {
            FlowBarPanel.shared.hideSoon()
            return
        }

        AppState.shared.history.insert(
            TranscriptEntry(text: final, appName: appName, date: Date(), durationSeconds: duration),
            at: 0)

        if targetIsTextInput {
            targetApp?.activate()
            try? await Task.sleep(nanoseconds: 150_000_000)
            TextInserter.insert(final)
            // Learn from whatever the user edits in the field afterwards.
            try? await Task.sleep(nanoseconds: 400_000_000)   // let the paste land
            EditWatcher.shared.watch(inserted: final, appName: appName)
            FlowBarPanel.shared.hideSoon()
        } else {
            // No editable field focused: park it on the clipboard instead.
            TextInserter.copyToClipboard(final)
            notice = "Copied to clipboard — ⌘V to paste"
            FlowBarPanel.shared.hideSoon(after: 2.2)
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                self?.notice = nil
            }
        }
    }

    func cancel() {
        guard isDictating else { return }
        sessionTimer?.invalidate()
        transcriber.cancel()
        state = .idle
        if AppState.shared.settings.playSounds { Sounds.play("Bottle") }
        FlowBarPanel.shared.hideSoon()
    }
}

func pasteLastTranscript() {
    guard let last = AppState.shared.history.first else { NSSound.beep(); return }
    TextInserter.insert(last.text)
}

enum Sounds {
    static func play(_ name: String) {
        NSSound(named: NSSound.Name(name))?.play()
    }
}
