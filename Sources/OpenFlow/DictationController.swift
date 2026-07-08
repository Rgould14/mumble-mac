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
    let transcriber = SpeechTranscriber()
    let hotkeys = HotkeyMonitor()

    private var startedAt = Date()
    private var targetApp: NSRunningApplication?
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
        do {
            try transcriber.start(locale: Locale(identifier: settings.localeIdentifier),
                                  onDeviceOnly: settings.onDeviceOnly)
        } catch {
            NSSound.beep()
            return
        }
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
        transcriber.stop { [weak self] raw in
            guard let self else { return }
            let polished = TextPolisher.polish(raw, state: AppState.shared)
            defer {
                self.state = .idle
                FlowBarPanel.shared.hideSoon()
            }
            guard !polished.isEmpty else { return }
            AppState.shared.history.insert(
                TranscriptEntry(text: polished,
                                appName: self.targetApp?.localizedName ?? "Unknown",
                                date: Date(),
                                durationSeconds: duration),
                at: 0)
            // Re-focus the app the user was dictating into, then paste.
            self.targetApp?.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                TextInserter.insert(polished)
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
