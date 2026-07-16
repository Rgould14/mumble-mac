import AppKit
import SwiftUI
import AVFoundation
import Speech

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

    func applicationWillTerminate(_ notification: Notification) {
        // Put the user's input device back if we switched it to the built-in mic.
        SpeechTranscriber.restoreOriginalDefaultInput()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
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
        appMenu.addItem(withTitle: "Quit OpenFlow",
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
