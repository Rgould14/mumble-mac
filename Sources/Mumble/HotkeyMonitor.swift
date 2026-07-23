import AppKit

/// Global keyboard monitor replicating Wispr Flow's activation gestures:
///  - Hold fn            -> push-to-talk (release to finish)
///  - Double-tap fn      -> hands-free toggle on; single fn tap stops
///  - fn + Space         -> hands-free toggle
///  - Ctrl + Option hold -> push-to-talk fallback for non-Apple keyboards
///  - Esc                -> cancel active dictation
///  - Cmd + Ctrl + V     -> paste last transcript
/// Requires Accessibility permission for global event monitoring.
final class HotkeyMonitor {
    var onPushToTalkDown: () -> Void = {}
    var onPushToTalkUp: () -> Void = {}
    /// Push-to-talk for the configured secondary language (down/up).
    var onSecondaryDown: () -> Void = {}
    var onSecondaryUp: () -> Void = {}
    var onHandsFreeToggle: () -> Void = {}
    var onPromptToggle: () -> Void = {}
    var onCancel: () -> Void = {}
    var onPasteLast: () -> Void = {}

    /// Set by the controller so Esc/space handling knows a session is live.
    var isDictating: () -> Bool = { false }
    var settings: () -> AppSettings = { AppSettings() }

    private var monitors: [Any] = []
    private var fnIsDown = false
    private var ctrlOptDown = false
    private var lastFnTapAt: TimeInterval = 0
    private var fnDownAt: TimeInterval = 0
    private var fnUsedAsChord = false
    private var pttActive = false
    private var secondaryDown = false

    static var hasAccessibilityPermission: Bool { AXIsProcessTrusted() }

    /// Global key-event monitors additionally require Input Monitoring on
    /// modern macOS — Accessibility alone is not enough for flagsChanged/keyDown.
    static var hasInputMonitoringPermission: Bool { CGPreflightListenEventAccess() }

    static func promptForInputMonitoring() {
        CGRequestListenEventAccess()   // triggers the Input Monitoring prompt
    }

    static func promptForAccessibility() {
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
    }

    func start() {
        stop()
        let flagsHandler: (NSEvent) -> Void = { [weak self] e in self?.handleFlags(e) }
        let keyHandler: (NSEvent) -> Void = { [weak self] e in self?.handleKeyDown(e) }
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: flagsHandler) as Any)
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: keyHandler) as Any)
        // Local monitors so shortcuts also work while our own windows are focused.
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { e in flagsHandler(e); return e } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            keyHandler(e)
            // Swallow Esc while dictating so it only cancels the session.
            if e.keyCode == 53, self?.isDictating() == true { return nil }
            return e
        } as Any)
    }

    func stop() {
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors = []
    }

    private var debugFlagCount = 0

    private func handleFlags(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Secondary-language push-to-talk on a dedicated right-side modifier.
        // flagsChanged fires for the specific key by keyCode; the matching
        // modifier flag tells us whether it went down or up.
        if let code = settings().secondaryKey.keyCode {
            if event.keyCode == code {
                let mod: NSEvent.ModifierFlags = code == 54 ? .command : (code == 61 ? .option : .control)
                let isDown = flags.contains(mod)
                if isDown && !secondaryDown {
                    secondaryDown = true
                    onSecondaryDown()
                    return
                } else if !isDown && secondaryDown {
                    secondaryDown = false
                    onSecondaryUp()
                    return
                }
            }
        }

        if settings().useFnKey {
            let fn = flags.contains(.function)
            if fn && !fnIsDown {
                fnIsDown = true
                fnUsedAsChord = false
                fnDownAt = Date.timeIntervalSinceReferenceDate
                if settings().gesture == .hold {
                    pttActive = true
                    onPushToTalkDown()
                }
            } else if !fn && fnIsDown {
                fnIsDown = false
                let now = Date.timeIntervalSinceReferenceDate
                if pttActive {
                    pttActive = false
                    // A tap shorter than 0.35s is a tap, not a hold: treat
                    // double-tap as hands-free on, single tap as stop/no-op.
                    if now - fnDownAt < 0.35 {
                        onPushToTalkUp()
                        if !fnUsedAsChord {
                            if now - lastFnTapAt < 0.4 { onHandsFreeToggle() }
                            else if isDictating() { onHandsFreeToggle() } // single tap stops hands-free
                            lastFnTapAt = now
                        }
                    } else {
                        onPushToTalkUp()
                    }
                } else if !fnUsedAsChord && now - fnDownAt < 0.35 {
                    if now - lastFnTapAt < 0.4 || isDictating() { onHandsFreeToggle() }
                    lastFnTapAt = now
                }
            }
        } else {
            // Ctrl+Option push-to-talk (Wispr's non-Apple-keyboard default).
            let down = flags.contains(.control) && flags.contains(.option) && !flags.contains(.command)
            if down && !ctrlOptDown {
                ctrlOptDown = true
                onPushToTalkDown()
            } else if !down && ctrlOptDown {
                ctrlOptDown = false
                onPushToTalkUp()
            }
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Esc cancels.
        if event.keyCode == 53, isDictating() {
            onCancel()
            return
        }
        // fn + Space -> hands-free toggle.
        if event.keyCode == 49, flags.contains(.function) {
            fnUsedAsChord = true
            pttActive = false
            onHandsFreeToggle()
            return
        }
        // fn + P -> Prompt Mode toggle.
        if event.keyCode == 35, flags.contains(.function) {
            fnUsedAsChord = true
            pttActive = false
            onPromptToggle()
            return
        }
        // Any key while fn held means fn was a chord, not push-to-talk.
        if flags.contains(.function) { fnUsedAsChord = true }
        // Cmd + Ctrl + V -> paste last transcript.
        if event.charactersIgnoringModifiers?.lowercased() == "v",
           flags.contains(.command), flags.contains(.control) {
            onPasteLast()
        }
    }
}
