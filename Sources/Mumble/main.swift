import AppKit
import SwiftUI
import AVFoundation
import Speech

/// Window management for the menu-bar + Dock hybrid app.
enum AppWindows {
    static var hub: NSWindow?
    static var onboarding: NSWindow?

    static func showHub() {
        if hub == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 560),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
            w.title = "Mumble"
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
            w.title = "Welcome to Mumble"
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

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var languageMenu: NSMenu!

    func applicationWillTerminate(_ notification: Notification) {
        // Put the user's input device back if we switched it to the built-in mic.
        SpeechTranscriber.restoreOriginalDefaultInput()
    }

    /// Dock icon click with no open windows (launch, or after closing the Hub) — bring up
    /// the Hub instead of doing nothing, which is what a windowless Dock click would do by default.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            AppWindows.showHub()
        }
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // .regular (not .accessory) gives Mumble a Dock icon and Cmd+Tab presence, so it can
        // be launched from the Dock instead of only via the menu-bar item.
        NSApp.setActivationPolicy(.regular)
        Log.line("launch — accessibility=\(HotkeyMonitor.hasAccessibilityPermission) inputMonitoring=\(HotkeyMonitor.hasInputMonitoringPermission) mic=\(AVCaptureDevice.authorizationStatus(for: .audio).rawValue) speech=\(SFSpeechRecognizer.authorizationStatus().rawValue)")
        if !HotkeyMonitor.hasInputMonitoringPermission {
            HotkeyMonitor.promptForInputMonitoring()
        }
        setupMainMenu()
        setupStatusItem()

        // Always ensure mic + speech authorization is requested — not just during
        // first-run onboarding. Otherwise a reset/undetermined Speech grant never
        // re-prompts and recognition silently returns nothing.
        SpeechTranscriber.requestPermissions { _ in }

        if AppState.shared.settings.hasCompletedOnboarding {
            DictationController.shared.startMonitoring()
            if !HotkeyMonitor.hasAccessibilityPermission {
                HotkeyMonitor.promptForAccessibility()
            }
        } else {
            AppWindows.showOnboarding()
        }
    }

    /// Accessory apps have no menu bar UI, but a main menu is still required for
    /// standard key equivalents (⌘V/⌘C/⌘X/⌘A/⌘Z) to reach text fields.
    private func setupMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Mumble",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All",
                     action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit

        NSApp.mainMenu = main
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let logo = Bundle.main.resourceURL.flatMap { NSImage(contentsOf: $0.appendingPathComponent("MenuBarIcon.png")) }
        // Template mode lets AppKit recolor the (black, transparent-bg) logo for light/dark
        // menu bars and the selected/highlighted state, same as a monochrome SF Symbol would.
        logo?.isTemplate = true
        logo?.size = NSSize(width: 18, height: 18)
        statusItem.button?.image = logo ?? NSImage(systemSymbolName: "waveform",
                                                     accessibilityDescription: "Mumble")

        let menu = NSMenu()
        menu.addItem(withTitle: "Start hands-free dictation (fn + Space)",
                     action: #selector(toggleHandsFree), keyEquivalent: "")
        menu.addItem(withTitle: "Start prompt dictation (fn + P)",
                     action: #selector(togglePrompt), keyEquivalent: "")
        menu.addItem(withTitle: "Paste last transcript (⌘⌃V)",
                     action: #selector(pasteLast), keyEquivalent: "")
        let langItem = NSMenuItem(title: "Dictation language", action: nil, keyEquivalent: "")
        languageMenu = NSMenu(title: "Dictation language")
        languageMenu.delegate = self
        langItem.submenu = languageMenu
        menu.addItem(langItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open Mumble Hub…", action: #selector(openHub), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Mumble", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === languageMenu else { return }
        menu.removeAllItems()
        let current = SpeechLocales.normalize(AppState.shared.settings.localeIdentifier)
        for id in SpeechLocales.favorites(current: current) {
            let item = NSMenuItem(title: SpeechLocales.displayName(id),
                                  action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.representedObject = id
            item.state = id == current ? .on : .off
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let more = NSMenuItem(title: "All languages…", action: #selector(openHub), keyEquivalent: "")
        more.target = self
        menu.addItem(more)
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        AppState.shared.settings.localeIdentifier = id
        Log.line("dictation language -> \(id)")
    }

    @objc private func toggleHandsFree() { DictationController.shared.toggleHandsFree() }
    @objc private func togglePrompt() { DictationController.shared.togglePromptMode() }
    @objc private func pasteLast() { pasteLastTranscript() }
    @objc private func openHub() { AppWindows.showHub() }
    @objc private func quit() { NSApp.terminate(nil) }
}

// One-time migration from the app's previous name: move the old OpenFlow
// support directory (settings incl. API key, history, dictionary, snippets,
// learned corrections) to Mumble. Must run before AppState/Log first touch it.
func migrateLegacySupportDirectory() {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let old = base.appendingPathComponent("OpenFlow")
    let new = base.appendingPathComponent("Mumble")
    if FileManager.default.fileExists(atPath: old.path),
       !FileManager.default.fileExists(atPath: new.path) {
        try? FileManager.default.moveItem(at: old, to: new)
    }
}
migrateLegacySupportDirectory()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
