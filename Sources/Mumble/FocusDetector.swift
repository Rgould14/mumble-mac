import AppKit
import ApplicationServices

/// Decides whether dictation should paste into the focused element or fall
/// back to the clipboard. Philosophy (matching Wispr Flow): DEFAULT TO
/// INSERTING — only use the clipboard when focus is clearly not editable.
/// Electron/Chromium apps (Claude, Slack, VS Code, Discord…) don't expose
/// their text fields via AX until poked with AXManualAccessibility, so an
/// honest "is this a text field?" is often unanswerable; a false "no" costs
/// the user their paste, a false "yes" pastes harmlessly.
enum FocusTarget {
    case textInput      // definitely editable → paste (restore clipboard after)
    case ambiguous      // opaque (Electron/web) → paste AND keep on clipboard
    case notEditable    // clearly not editable → clipboard only
}

enum FocusDetector {
    static func classifyFocus() -> FocusTarget {
        if isDefinitelyTextInput() { return .textInput }

        // Electron/Chromium builds its AX tree lazily — request it and retry.
        if let app = NSWorkspace.shared.frontmostApplication {
            let appEl = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetAttributeValue(appEl, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            usleep(150_000)
            if isDefinitelyTextInput() { return .textInput }
        }

        guard let element = focusedElement() else {
            // Electron apps often expose NO focused element at all even when the
            // user is in a text box — treat invisible focus as ambiguous, not
            // as "nothing focused".
            return NSWorkspace.shared.frontmostApplication != nil ? .ambiguous : .notEditable
        }
        return nonEditableRoles.contains(role(of: element)) ? .notEditable : .ambiguous
    }

    private static func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString,
                                            &ref) == .success,
              let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(ref as AnyObject, to: AXUIElement.self)
    }

    private static func role(of element: AXUIElement) -> String {
        var ref: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &ref)
        return ref as? String ?? ""
    }

    private static func isDefinitelyTextInput() -> Bool {
        guard let element = focusedElement() else { return false }
        let r = role(of: element)
        if ["AXTextField", "AXTextArea", "AXSearchField", "AXComboBox"].contains(r) {
            return true
        }
        if r == "AXStaticText" { return false }

        var settable = DarwinBoolean(false)
        if AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString,
                                          &settable) == .success, settable.boolValue {
            return true
        }
        var namesRef: CFArray?
        if AXUIElementCopyAttributeNames(element, &namesRef) == .success,
           let names = namesRef as? [String],
           names.contains(kAXSelectedTextRangeAttribute as String) {
            return true
        }
        return false
    }

    /// Roles that can never accept typed text — those go to the clipboard.
    /// Unknown/opaque roles (AXGroup, AXWebArea…) count as ambiguous.
    private static let nonEditableRoles: Set<String> = [
        "AXButton", "AXStaticText", "AXImage", "AXMenuItem", "AXMenu",
        "AXMenuBar", "AXMenuBarItem", "AXCheckBox", "AXRadioButton",
        "AXPopUpButton", "AXLink", "AXList", "AXTable", "AXOutline",
        "AXRow", "AXCell", "AXColumn", "AXToolbar", "AXTabGroup",
        "AXSlider", "AXValueIndicator", "AXDisclosureTriangle",
    ]
}
