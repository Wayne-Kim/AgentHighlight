import ApplicationServices
import Foundation

struct AXElement {
    let raw: AXUIElement

    static func application(pid: Int32) -> AXElement {
        AXElement(raw: AXUIElementCreateApplication(pid))
    }

    func attribute<T>(_ name: String) -> T? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(raw, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    var role: String? { attribute(kAXRoleAttribute) }
    var title: String? { attribute(kAXTitleAttribute) }
    var value: String? { attribute(kAXValueAttribute) }
    var elementDescription: String? { attribute(kAXDescriptionAttribute) }
    var isMinimized: Bool { attribute(kAXMinimizedAttribute) ?? false }

    var children: [AXElement] {
        let raws: [AXUIElement] = attribute(kAXChildrenAttribute) ?? []
        return raws.map(AXElement.init)
    }

    var windows: [AXElement] {
        let raws: [AXUIElement] = attribute(kAXWindowsAttribute) ?? []
        return raws.map(AXElement.init)
    }

    var focusedWindow: AXElement? {
        guard let raw: AXUIElement = attribute(kAXFocusedWindowAttribute) else { return nil }
        return AXElement(raw: raw)
    }

    var frame: CGRect? {
        guard let position: CGPoint = axValue(kAXPositionAttribute, type: .cgPoint, initial: .zero),
              let size: CGSize = axValue(kAXSizeAttribute, type: .cgSize, initial: .zero) else { return nil }
        return CGRect(origin: position, size: size)
    }

    func perform(_ action: String) -> Bool {
        AXUIElementPerformAction(raw, action as CFString) == .success
    }

    func boundsForRange(_ range: NSRange) -> CGRect? {
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let parameter = AXValueCreate(.cfRange, &cfRange) else { return nil }
        var out: AnyObject?
        let status = AXUIElementCopyParameterizedAttributeValue(
            raw, kAXBoundsForRangeParameterizedAttribute as CFString, parameter, &out
        )
        guard status == .success, let out, CFGetTypeID(out) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(out as! AXValue, .cgRect, &rect), rect.width > 0, rect.height > 0 else { return nil }
        return rect
    }

    func enableWebAccessibility() {
        AXUIElementSetAttributeValue(raw, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(raw, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    func setMessagingTimeout(_ seconds: Float) {
        AXUIElementSetMessagingTimeout(raw, seconds)
    }

    private func axValue<T>(_ name: String, type: AXValueType, initial: T) -> T? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(raw, name as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var result = initial
        guard AXValueGetValue(value as! AXValue, type, &result) else { return nil }
        return result
    }
}
