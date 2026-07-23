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
    /// True while the current session is a Prompt Mode dictation.
    @Published var promptMode = false
    /// Locale used for the current session (shown on the HUD).
    @Published var activeLocale = ""
    private var localeOverride: String?
    /// Short outcome message shown in the Flow Bar after a session (e.g. copied).
    @Published var notice: String?
    let transcriber = SpeechTranscriber()
    let hotkeys = HotkeyMonitor()

    private var startedAt = Date()
    private var targetApp: NSRunningApplication?
    private var focusTarget: FocusTarget = .notEditable
    private var sessionTimer: Timer?

    var isDictating: Bool { if case .recording = state { return true }; return false }

    private init() {
        hotkeys.isDictating = { [weak self] in self?.isDictating ?? false }
        hotkeys.settings = { AppState.shared.settings }
        hotkeys.onPushToTalkDown = { [weak self] in self?.pushToTalkDown() }
        hotkeys.onPushToTalkUp = { [weak self] in self?.pushToTalkUp() }
        hotkeys.onHandsFreeToggle = { [weak self] in self?.toggleHandsFree() }
        hotkeys.onPromptToggle = { [weak self] in self?.togglePromptMode() }
        hotkeys.onSecondaryDown = { [weak self] in self?.secondaryDown() }
        hotkeys.onSecondaryUp = { [weak self] in self?.secondaryUp() }
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

    private func secondaryDown() {
        guard case .idle = state else { return }
        localeOverride = AppState.shared.settings.secondaryLocaleIdentifier
        start(handsFree: false)
    }

    private func secondaryUp() {
        if case .recording(handsFree: false) = state {
            let held = Date().timeIntervalSince(startedAt)
            if held < 0.25 { cancel() } else { stopAndInsert() }
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

    /// fn+P: dictate a rambled intent; Mumble rewrites it into an engineered
    /// prompt for the inferred target before inserting.
    func togglePromptMode() {
        switch state {
        case .idle:
            start(handsFree: true, prompt: true)
        case .recording:
            // fn+P arrives moments after the fn hold already started a PTT
            // session — upgrade it to Prompt Mode instead of stopping it, and
            // make it hands-free so releasing fn doesn't end it.
            if !promptMode, Date().timeIntervalSince(startedAt) < 2.0 {
                promptMode = true
                state = .recording(handsFree: true)
                Log.line("session upgraded to prompt mode")
            } else {
                stopAndInsert()
            }
        default: break
        }
    }

    // MARK: Session

    func start(handsFree: Bool, prompt: Bool = false) {
        guard case .idle = state else { return }
        promptMode = prompt
        let settings = AppState.shared.settings
        let locale = localeOverride ?? settings.localeIdentifier
        activeLocale = locale
        targetApp = NSWorkspace.shared.frontmostApplication
        // Decide the destination now, while the user's click focus is intact.
        focusTarget = FocusDetector.classifyFocus()
        Log.line("target app=\(targetApp?.localizedName ?? "?") focus=\(focusTarget)")
        notice = nil
        do {
            try transcriber.start(locale: Locale(identifier: locale),
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
        if promptMode {
            let target = PromptTarget.infer(
                appName: appName,
                fallback: PromptTarget(rawValue: AppState.shared.settings.promptDefaultTarget) ?? .general)
            Log.line("prompt mode: target=\(target.rawValue)")
            do {
                text = try await PromptRewriter.rewrite(raw, target: target, state: AppState.shared)
            } catch {
                // No key/offline: fall back to normal cleanup so nothing is lost.
                text = (try? await LLMCleanup.clean(raw, appName: appName, state: AppState.shared))
                    ?? TextPolisher.polish(raw, state: AppState.shared)
            }
            promptMode = false
        } else {
            do {
                text = try await LLMCleanup.clean(raw, appName: appName, state: AppState.shared)
            } catch {
                text = TextPolisher.polish(raw, state: AppState.shared)
            }
        }
        // Snippet expansion + dictionary + learned corrections apply locally on
        // top of the LLM output.
        let final = LearnedCorrections.apply(
            TextPolisher.postProcess(text, state: AppState.shared),
            state: AppState.shared)

        state = .idle
        localeOverride = nil
        guard !final.isEmpty else {
            FlowBarPanel.shared.hideSoon()
            return
        }

        AppState.shared.history.insert(
            TranscriptEntry(text: final, appName: appName, date: Date(), durationSeconds: duration),
            at: 0)

        Log.line("insert path: \(focusTarget) chars=\(final.count)")
        switch focusTarget {
        case .textInput:
            targetApp?.activate()
            try? await Task.sleep(nanoseconds: 150_000_000)
            TextInserter.insert(final)   // restores the user's clipboard after
            try? await Task.sleep(nanoseconds: 400_000_000)   // let the paste land
            EditWatcher.shared.watch(inserted: final, appName: appName)
            FlowBarPanel.shared.hideSoon()
        case .ambiguous:
            // Opaque focus (Electron/web): paste AND keep the text on the
            // clipboard, so it lands in the field when one is focused and is
            // never lost when one isn't.
            targetApp?.activate()
            try? await Task.sleep(nanoseconds: 150_000_000)
            TextInserter.copyToClipboard(final)
            TextInserter.pasteKeystrokeOnly()
            try? await Task.sleep(nanoseconds: 400_000_000)
            EditWatcher.shared.watch(inserted: final, appName: appName)
            FlowBarPanel.shared.hideSoon()
        case .notEditable:
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
        localeOverride = nil
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
