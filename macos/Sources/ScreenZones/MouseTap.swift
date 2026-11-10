import CoreGraphics

@MainActor
protocol MouseHandler: AnyObject {
    func mouseDown(at point: CGPoint, clicks: Int64) -> Bool
    func mouseUp(at point: CGPoint) -> Bool
    func tapDisabled()
}

private let tapCallback: CGEventTapCallBack = { _, type, event, refcon in
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<MouseTap>.fromOpaque(refcon).takeUnretainedValue()
    let location = event.location
    let clicks = event.getIntegerValueField(.mouseEventClickState)
    let swallow = MainActor.assumeIsolated { tap.dispatch(type, location, clicks) }
    return swallow ? nil : Unmanaged.passUnretained(event)
}

@MainActor
final class MouseTap {
    weak var handler: MouseHandler?
    private var clicks: CFMachPort?

    var isEnabled: Bool { clicks.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    func start() -> Bool {
        if clicks == nil {
            let mask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue) | CGEventMask(1 << CGEventType.leftMouseUp.rawValue)
            clicks = install(mask)
        }
        if let clicks { CGEvent.tapEnable(tap: clicks, enable: true) }
        return clicks != nil
    }

    func stop() {
        if let clicks { CGEvent.tapEnable(tap: clicks, enable: false) }
    }

    fileprivate func dispatch(_ type: CGEventType, _ location: CGPoint, _ clicks: Int64) -> Bool {
        switch type {
        case .leftMouseDown: return handler?.mouseDown(at: location, clicks: clicks) ?? false
        case .leftMouseUp: return handler?.mouseUp(at: location) ?? false
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            handler?.tapDisabled()
            return false
        default: return false
        }
    }

    private func install(_ mask: CGEventMask) -> CFMachPort? {
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: tapCallback,
            userInfo: refcon
        ) else { return nil }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, port, 0), .commonModes)
        return port
    }
}
