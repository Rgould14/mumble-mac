import AppKit
import SwiftUI

/// Window management for an LSUIElement (menu-bar) app.
enum AppWindows {
    static var hub: NSWindow?
    static var onboarding: NSWindow?

    static func showHub() {
        if hub == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 560),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
            w.title = "OpenFlow"
            w.contentView = NSHostingView(rootView: HubView())
            w.center()
            w.isReleasedWhenClosed = false
            hub = w
        }
        NSApp.activate(ignoringOtherApps: true)
        hub?.makeKeyAndOrderFront(nil)
    }

    static func showOnboarding() {
        if onboarding == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 460),
                             styleMask: [.titled, .closable],
                             backing: .buffered, defer: false)
            w.title = "Welcome to OpenFlow"
            w.contentView = NSHostingView(rootView: OnboardingView())
            w.center()
            w.isReleasedWhenClosed = false
            onboarding = w
        }
        NSApp.activate(ignoringOtherApps: true)
        onboarding?.makeKeyAndOrderFront(nil)
    }

    static func closeOnboarding() { onboarding?.orderOut(nil) }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()

        if AppState.shared.settings.hasCompletedOnboarding {
            DictationController.shared.startMonitoring()
            if !HotkeyMonitor.hasAccessibilityPermission {
                HotkeyMonitor.promptForAccessibility()
            }
        } else {
            SpeechTranscriber.requestPermissions { _ in }
            AppWindows.showOnboarding()
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "waveform",
                                           accessibilityDescription: "OpenFlow")

        let menu = NSMenu()
        menu.addItem(withTitle: "Start hands-free dictation (fn + Space)",
                     action: #selector(toggleHandsFree), keyEquivalent: "")
        menu.addItem(withTitle: "Paste last transcript (⌘⌃V)",
                     action: #selector(pasteLast), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open Flow Hub…", action: #selector(openHub), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit OpenFlow", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        statusItem.menu = menu
    }

    @objc private func toggleHandsFree() { DictationController.shared.toggleHandsFree() }
    @objc private func pasteLast() { pasteLastTranscript() }
    @objc private func openHub() { AppWindows.showHub() }
    @objc private func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
