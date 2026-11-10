import AppKit
import ApplicationServices

func app(_ bundle: String) -> AXUIElement? {
    NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first.map { AXUIElementCreateApplication($0.processIdentifier) }
}
func attr(_ e: AXUIElement, _ n: String) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(e, n as CFString, &v) == .success ? v : nil
}
func frame(_ w: AXUIElement) -> CGRect {
    var p = CGPoint.zero, s = CGSize.zero
    if let v = attr(w, kAXPositionAttribute) { AXValueGetValue(v as! AXValue, .cgPoint, &p) }
    if let v = attr(w, kAXSizeAttribute) { AXValueGetValue(v as! AXValue, .cgSize, &s) }
    return CGRect(origin: p, size: s)
}
func windows(_ bundle: String) -> [AXUIElement] {
    guard let a = app(bundle) else { return [] }
    return (attr(a, kAXWindowsAttribute) as? [AXUIElement] ?? []).filter { (attr($0, kAXSubroleAttribute) as? String) == kAXStandardWindowSubrole }
}
func post(_ type: CGEventType, _ p: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)!.post(tap: .cghidEventTap)
}
let a = CommandLine.arguments
switch a[1] {
case "frames":
    for w in windows(a[2]) {
        let f = frame(w)
        print(String(format: "x=%.0f y=%.0f w=%.0f h=%.0f full=%@ title=%@", f.minX, f.minY, f.width, f.height,
                     (attr(w, "AXFullScreen") as? Bool ?? false) ? "yes" : "no", (attr(w, kAXTitleAttribute) as? String ?? "") as NSString))
    }
case "move":
    guard let w = windows(a[2]).first else { print("no window"); exit(1) }
    var p = CGPoint(x: Double(a[3])!, y: Double(a[4])!)
    AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &p)!)
case "drag":
    let from = CGPoint(x: Double(a[2])!, y: Double(a[3])!), to = CGPoint(x: Double(a[4])!, y: Double(a[5])!)
    post(.mouseMoved, from); usleep(80_000)
    post(.leftMouseDown, from); usleep(120_000)
    for i in 1...25 {
        let t = Double(i) / 25
        post(.leftMouseDragged, CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t))
        usleep(16_000)
    }
    usleep(120_000)
    post(.leftMouseUp, to)
case "click":
    let p = CGPoint(x: Double(a[2])!, y: Double(a[3])!)
    post(.mouseMoved, p); usleep(80_000)
    post(.leftMouseDown, p); usleep(60_000); post(.leftMouseUp, p)
case "zoom":
    guard let w = windows(a[2]).first else { print("no window"); exit(1) }
    for name in [kAXZoomButtonAttribute, kAXFullScreenButtonAttribute] {
        if let b = attr(w, name), CFGetTypeID(b) == AXUIElementGetTypeID() {
            let f = frame(b as! AXUIElement)
            print(String(format: "%@ x=%.0f y=%.0f w=%.0f h=%.0f", name as NSString, f.midX, f.midY, f.width, f.height))
        }
    }
default: print("unknown")
}
