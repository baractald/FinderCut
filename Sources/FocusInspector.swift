import AppKit
import ApplicationServices

enum FocusInspector {
    private static let textEditingRoles: Set<String> = [
        kAXTextFieldRole as String,
        kAXTextAreaRole as String,
        kAXComboBoxRole as String,
        "AXSearchField",
        "AXWebArea",
        "AXSecureTextField",
        "AXTokenField"
    ]

    private static let textEditingSubroles: Set<String> = [
        "AXSearchField",
        "AXSecureTextField",
        "AXTextInput"
    ]

    private static let bypassedWindowSubroles: Set<String> = [
        "AXSheet",
        "AXSystemFloatingWindow",
        "AXFloatingWindow"
    ]

    /// Returns the live bundle identifier of the focused application (avoids stale NSWorkspace cache on Desktop).
    static func focusedApplicationBundleID() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var appObj: CFTypeRef?
        if AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &appObj) == .success,
           let appEl = appObj {
            var pid: pid_t = 0
            if AXUIElementGetPid(appEl as! AXUIElement, &pid) == .success,
               let bid = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier {
                return bid
            }
        }
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    static func isTextEditing(role: String?, subrole: String?) -> Bool {
        if let role = role, textEditingRoles.contains(role) {
            return true
        }
        if let subrole = subrole, textEditingSubroles.contains(subrole) {
            return true
        }
        return false
    }

    static func isBypassedWindow(role: String?, subrole: String?, identifier: String?) -> Bool {
        if role == "AXSheet" {
            return true
        }
        if let subrole = subrole, bypassedWindowSubroles.contains(subrole) {
            return true
        }
        if let identifier = identifier?.lowercased(),
           identifier.contains("quicklook") || identifier.contains("qlpreview") {
            return true
        }
        return false
    }

    /// Returns true if the focused UI element (or its enclosing dialog/Quick Look preview) should receive native Cmd+X/V.
    static func isFocusedElementTextInput() -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedObj: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedObj
        )

        guard result == .success, let focused = focusedObj else {
            return isFocusedWindowBypassed(systemWide: systemWide)
        }

        var currentElement: AXUIElement? = (focused as! AXUIElement)
        for _ in 0..<3 {
            guard let element = currentElement else { break }
            let role = stringAttribute(kAXRoleAttribute as CFString, on: element)
            let subrole = stringAttribute(kAXSubroleAttribute as CFString, on: element)
            if isTextEditing(role: role, subrole: subrole) {
                return true
            }
            currentElement = elementAttribute(kAXParentAttribute as CFString, on: element)
        }

        let focusedElement = focused as! AXUIElement
        if let window = elementAttribute(kAXWindowAttribute as CFString, on: focusedElement) {
            if isBypassedWindowElement(window) {
                return true
            }
        } else if isFocusedWindowBypassed(systemWide: systemWide) {
            return true
        }

        return false
    }

    private static func isFocusedWindowBypassed(systemWide: AXUIElement) -> Bool {
        guard let app = elementAttribute(kAXFocusedApplicationAttribute as CFString, on: systemWide),
              let window = elementAttribute(kAXFocusedWindowAttribute as CFString, on: app) else {
            return false
        }
        return isBypassedWindowElement(window)
    }

    private static func isBypassedWindowElement(_ window: AXUIElement) -> Bool {
        let role = stringAttribute(kAXRoleAttribute as CFString, on: window)
        let subrole = stringAttribute(kAXSubroleAttribute as CFString, on: window)
        let identifier = stringAttribute("AXIdentifier" as CFString, on: window)
        return isBypassedWindow(role: role, subrole: subrole, identifier: identifier)
    }

    private static func stringAttribute(_ attribute: CFString, on element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private static func elementAttribute(_ attribute: CFString, on element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let raw = value,
              CFGetTypeID(raw) == AXUIElementGetTypeID() else {
            return nil
        }
        return (raw as! AXUIElement)
    }
}
