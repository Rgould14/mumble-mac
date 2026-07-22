import AppKit
import ApplicationServices

/// Detects whether the element with keyboard focus (system-wide) is an editable
/// text input, via the Accessibility API. Used to decide paste vs clipboard-only.
enum FocusDetector {
    static func focusedElementIsTextInput() -> Bool {
        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString,
                                            &focusedRef) == .success,
              let ref = focusedRef, CFGetTypeID(ref) == AXUIElementGetTypeID() else {
            return false
        }
        let element = unsafeDowncast(ref as AnyObject, to: AXUIElement.self)

        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String ?? ""
        if ["AXTextField", "AXTextArea", "AXSearchField", "AXComboBox"].contains(role) {
            return true
        }
        if role == "AXStaticText" { return false }

        // Web/Electron editors (contenteditable) often expose a generic role but
        // support text-editing attributes: a settable AXValue or AXSelectedTextRange.
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
}
