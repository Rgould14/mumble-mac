import AppKit
import Carbon.HIToolbox

/// Inserts text into the frontmost app by putting it on the pasteboard and
/// synthesizing Cmd+V, then restoring the previous pasteboard contents.
enum TextInserter {
    static func insert(_ text: String) {
        let pb = NSPasteboard.general
        let saved = pb.pasteboardItems?.compactMap { item -> [NSPasteboard.PasteboardType: Data]? in
            var copy: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types { copy[type] = item.data(forType: type) }
            return copy.isEmpty ? nil : copy
        } ?? []

        pb.clearContents()
        pb.setString(text, forType: .string)
        pasteKeystroke()

        // Restore the user's clipboard after the paste lands.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            pb.clearContents()
            let items = saved.map { dict -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (type, data) in dict { item.setData(data, forType: type) }
                return item
            }
            if !items.isEmpty { pb.writeObjects(items) }
            else { pb.setString(text, forType: .string) }
        }
    }

    /// Put text on the clipboard permanently (no restore) — used when nothing
    /// editable has focus, so the user can ⌘V it wherever they want.
    static func copyToClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    /// Synthesize ⌘V without touching the pasteboard — used with
    /// copyToClipboard for the paste-and-keep flow on opaque (Electron) focus.
    static func pasteKeystrokeOnly() {
        pasteKeystroke()
    }

    private static func pasteKeystroke() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let vDown = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        let vUp = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
    }

    static var frontmostAppName: String {
        NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
    }
}
