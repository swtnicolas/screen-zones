import AppKit
import ApplicationServices

@_silgen_name("_AXUIElementGetWindow")
private func axWindowID(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

extension AXUIElement {
    func attribute(_ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success else { return nil }
        return value
    }

    func element(_ name: String) -> AXUIElement? {
        guard let value = attribute(name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    func set(_ name: String, _ value: CFTypeRef) {
        AXUIElementSetAttributeValue(self, name as CFString, value)
    }

    var subrole: String? { attribute(kAXSubroleAttribute) as? String }
    var title: String { attribute(kAXTitleAttribute) as? String ?? "" }
    var windows: [AXUIElement] { attribute(kAXWindowsAttribute) as? [AXUIElement] ?? [] }
    var focusedWindow: AXUIElement? { element(kAXFocusedWindowAttribute) }
    var isStandardWindow: Bool { subrole == kAXStandardWindowSubrole }
    var isFullScreen: Bool { attribute("AXFullScreen") as? Bool ?? false }
    var isMinimized: Bool { attribute(kAXMinimizedAttribute) as? Bool ?? false }

    var pid: pid_t? {
        var pid: pid_t = 0
        return AXUIElementGetPid(self, &pid) == .success ? pid : nil
    }

    var windowID: CGWindowID? {
        var id: CGWindowID = 0
        return axWindowID(self, &id) == .success && id != 0 ? id : nil
    }

    var frame: CGRect? {
        var values: CFArray?
        let names = [kAXPositionAttribute, kAXSizeAttribute] as CFArray
        guard AXUIElementCopyMultipleAttributeValues(self, names, AXCopyMultipleAttributeOptions(rawValue: 0), &values) == .success,
              let list = values as? [AnyObject], list.count == 2,
              CFGetTypeID(list[0]) == AXValueGetTypeID(), CFGetTypeID(list[1]) == AXValueGetTypeID()
        else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(unsafeDowncast(list[0], to: AXValue.self), .cgPoint, &origin)
        AXValueGetValue(unsafeDowncast(list[1], to: AXValue.self), .cgSize, &size)
        return CGRect(origin: origin, size: size)
    }

    func setOrigin(_ origin: CGPoint) {
        var point = origin
        if let value = AXValueCreate(.cgPoint, &point) { set(kAXPositionAttribute, value) }
    }

    func setSize(_ size: CGSize) {
        var extent = size
        if let value = AXValueCreate(.cgSize, &extent) { set(kAXSizeAttribute, value) }
    }

    func setFrame(_ frame: CGRect) {
        setSize(frame.size)
        setOrigin(frame.origin)
        setSize(frame.size)
    }

    func raise() {
        AXUIElementPerformAction(self, kAXRaiseAction as CFString)
    }

    func press(_ button: String) {
        guard let button = element(button) else { return }
        AXUIElementPerformAction(button, kAXPressAction as CFString)
    }

    func setMinimized(_ minimized: Bool) {
        set(kAXMinimizedAttribute, minimized ? kCFBooleanTrue : kCFBooleanFalse)
    }

    func focus() {
        guard let pid else { return }
        AXUIElementCreateApplication(pid).set(kAXFrontmostAttribute, kCFBooleanTrue)
        set(kAXMainAttribute, kCFBooleanTrue)
        raise()
    }
}
