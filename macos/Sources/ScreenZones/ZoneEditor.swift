import AppKit
import Carbon

@MainActor
final class ZoneEditor {
    private let panel = EditorPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
    private let previous = NSWorkspace.shared.frontmostApplication
    private let onClose: () -> Void

    init(title: String, zones: [Zone], frame: NSRect, panelScale: CGFloat, onSave: @escaping ([Zone]) -> Void, onClose: @escaping () -> Void) {
        self.onClose = onClose
        let view = EditorView(title: title, zones: zones, panelScale: panelScale)
        view.onSave = { [weak self] zones in
            onSave(zones)
            self?.close()
        }
        view.onCancel = { [weak self] in self?.close() }
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.colorSpace = .sRGB
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.contentView = view
        panel.setFrame(frame, display: false)
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(view)
    }

    func close() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        previous?.activate(options: [])
        onClose()
    }
}

private final class EditorPanel: FreePanel {
    override var canBecomeKey: Bool { true }
}

private final class EditorView: NSView {
    private enum Action: CaseIterable {
        case columns, rows, remove

        var symbol: String {
            switch self {
            case .columns: "rectangle.split.2x1"
            case .rows: "rectangle.split.1x2"
            case .remove: "xmark"
            }
        }
    }

    private static let shade = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.6)
    private static let accent = NSColor(srgbRed: 0.22, green: 0.42, blue: 0.82, alpha: 1)
    private static let tint = NSColor(srgbRed: 0.22, green: 0.42, blue: 0.82, alpha: 0.2)
    private static let control = NSColor(srgbRed: 0.18, green: 0.18, blue: 0.18, alpha: 1)
    private static let lit = NSColor(srgbRed: 0.32, green: 0.32, blue: 0.32, alpha: 1)
    private static let command = NSSize(width: 96, height: 28)
    private static let button = NSSize(width: 44, height: 32)
    private static let spacing: CGFloat = 8
    private static let grip: CGFloat = 16

    private static let images: [Action: NSImage] = {
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)]))
        var images: [Action: NSImage] = [:]
        for action in Action.allCases {
            images[action] = NSImage(systemSymbolName: action.symbol, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
        }
        return images
    }()

    private static let letter: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 44, weight: .semibold),
        .foregroundColor: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.95),
    ]

    private static let caption: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12),
        .foregroundColor: NSColor(srgbRed: 0.8, green: 0.8, blue: 0.8, alpha: 1),
    ]

    private static let commandTitle: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 13, weight: .medium),
        .foregroundColor: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
    ]

    var onSave: (([Zone]) -> Void)?
    var onCancel: (() -> Void)?
    private var zones: [Zone]
    private let panelScale: CGFloat
    private let help: String
    private let helpWidth: CGFloat
    private var hover: (index: Int, action: Action)?
    private var drag: (axis: Axis, from: Double)?

    init(title: String, zones: [Zone], panelScale: CGFloat) {
        self.zones = zones
        self.panelScale = panelScale
        help = "\(title) · Arrastra las líneas para cambiar los tamaños"
        helpWidth = (help as NSString).size(withAttributes: Self.caption).width.rounded(.up)
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var toolbar: NSRect {
        let width = 16 + helpWidth + 24 + Self.command.width * 2 + 8 + 12
        return NSRect(x: (bounds.midX - width / 2).rounded(), y: bounds.maxY - 76, width: width, height: 48)
    }

    private var saveButton: NSRect {
        let bar = toolbar
        return NSRect(x: bar.maxX - 12 - Self.command.width, y: (bar.midY - Self.command.height / 2).rounded(), width: Self.command.width, height: Self.command.height)
    }

    private var cancelButton: NSRect {
        saveButton.offsetBy(dx: -(Self.command.width + 8), dy: 0)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    override func draw(_ dirtyRect: NSRect) {
        Self.shade.setFill()
        bounds.fill()
        for (index, zone) in zones.enumerated() {
            let frame = rect(zone)
            let path = NSBezierPath(roundedRect: frame, xRadius: 8, yRadius: 8)
            Self.tint.setFill()
            path.fill()
            Self.accent.setStroke()
            path.lineWidth = 2
            path.stroke()
            draw(zone.id, centeredAt: NSPoint(x: frame.midX, y: frame.midY - 44), attributes: Self.letter)
            for (line, text) in captions(zone).enumerated() {
                draw(text, centeredAt: NSPoint(x: frame.midX, y: frame.midY - 8 + CGFloat(line) * 16), attributes: Self.caption)
            }
            for (action, button) in buttons(zone) {
                let enabled = result(action, at: index) != nil
                let highlighted = enabled && hover?.index == index && hover?.action == action
                (highlighted ? Self.lit : Self.control).setFill()
                NSBezierPath(roundedRect: button, xRadius: 6, yRadius: 6).fill()
                guard let image = Self.images[action] else { continue }
                let size = image.size
                image.draw(
                    in: NSRect(x: (button.midX - size.width / 2).rounded(), y: (button.midY - size.height / 2).rounded(), width: size.width, height: size.height),
                    from: .zero, operation: .sourceOver, fraction: enabled ? 1 : 0.3, respectFlipped: true, hints: nil
                )
            }
        }
        let bar = toolbar
        Self.control.setFill()
        NSBezierPath(roundedRect: bar, xRadius: 10, yRadius: 10).fill()
        let size = (help as NSString).size(withAttributes: Self.caption)
        (help as NSString).draw(at: NSPoint(x: bar.minX + 16, y: (bar.midY - size.height / 2).rounded()), withAttributes: Self.caption)
        for (title, frame, color) in [("Cancelar", cancelButton, Self.lit), ("Guardar", saveButton, Self.accent)] {
            color.setFill()
            NSBezierPath(roundedRect: frame, xRadius: 6, yRadius: 6).fill()
            draw(title, centeredAt: NSPoint(x: frame.midX, y: frame.midY), attributes: Self.commandTitle)
        }
    }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case kVK_Return, kVK_ANSI_KeypadEnter: onSave?(zones)
        case kVK_Escape: onCancel?()
        default: super.keyDown(with: event)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let next = control(at: point)
        if next?.index != hover?.index || next?.action != hover?.action {
            hover = next
            needsDisplay = true
        }
        (divider(at: point).map { $0.axis == .x ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown } ?? NSCursor.arrow).set()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if saveButton.contains(point) {
            onSave?(zones)
            return
        }
        if cancelButton.contains(point) {
            onCancel?()
            return
        }
        if let (index, action) = control(at: point) {
            guard let next = result(action, at: index) else { return }
            zones = next
            hover = nil
            needsDisplay = true
            return
        }
        drag = divider(at: point)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let current = drag else { return }
        let point = convert(event.locationInWindow, from: nil)
        let to = Double(current.axis == .x ? point.x / bounds.width : point.y / bounds.height)
        guard abs(to - current.from) > 0.0001,
              let next = Geometry.moving(zones, EdgeMove(axis: current.axis, from: current.from, to: to)) else { return }
        zones = next
        drag = (current.axis, (to * 10000).rounded() / 10000)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        drag = nil
    }

    private func rect(_ zone: Zone) -> NSRect {
        NSRect(x: zone.x * bounds.width, y: zone.y * bounds.height, width: zone.w * bounds.width, height: zone.h * bounds.height)
            .insetBy(dx: 4, dy: 4)
    }

    private func buttons(_ zone: Zone) -> [(Action, NSRect)] {
        let frame = rect(zone)
        let count = CGFloat(Action.allCases.count)
        let total = count * Self.button.width + (count - 1) * Self.spacing
        let y = (frame.midY + 38).rounded()
        return Action.allCases.enumerated().map { index, action in
            let x = (frame.midX - total / 2).rounded() + CGFloat(index) * (Self.button.width + Self.spacing)
            return (action, NSRect(x: x, y: y, width: Self.button.width, height: Self.button.height))
        }
    }

    private func result(_ action: Action, at index: Int) -> [Zone]? {
        switch action {
        case .columns: Geometry.splitting(zones, at: index, along: .x)
        case .rows: Geometry.splitting(zones, at: index, along: .y)
        case .remove: Geometry.removing(zones, at: index)
        }
    }

    private func control(at point: NSPoint) -> (index: Int, action: Action)? {
        for (index, zone) in zones.enumerated() {
            for (action, button) in buttons(zone) where button.contains(point) {
                return (index, action)
            }
        }
        return nil
    }

    private func divider(at point: NSPoint) -> (axis: Axis, from: Double)? {
        let placed = zones.map { PlacedZone($0, in: bounds, side: .top, size: 0) }
        let lines = Geometry.dividers(placed, in: bounds, thickness: 0).map { $0.insetBy(dx: -Self.grip / 2, dy: -Self.grip / 2) }
        guard let line = lines.first(where: { $0.contains(point) }) else { return nil }
        let axis: Axis = line.width < line.height ? .x : .y
        let value = Double(axis == .x ? line.midX / bounds.width : line.midY / bounds.height)
        let edges = zones.flatMap { axis == .x ? [$0.x, $0.x + $0.w] : [$0.y, $0.y + $0.h] }
        return edges.min { abs($0 - value) < abs($1 - value) }.map { (axis, $0) }
    }

    private func captions(_ zone: Zone) -> [String] {
        let placed = PlacedZone(zone, in: bounds, side: .top, size: 0)
        let full = placed.full.size
        return [
            "Zona: \(Int(full.width)) × \(Int(full.height)) px  ·  \(percent(zone.w)) % × \(percent(zone.h)) %",
            "Físicos: \(Int((full.width * panelScale).rounded())) × \(Int((full.height * panelScale).rounded())) px",
        ]
    }

    private func percent(_ value: Double) -> Int {
        Int((value * 100).rounded())
    }

    private func draw(_ text: String, centeredAt point: NSPoint, attributes: [NSAttributedString.Key: Any]) {
        let string = text as NSString
        let size = string.size(withAttributes: attributes)
        string.draw(at: NSPoint(x: (point.x - size.width / 2).rounded(), y: (point.y - size.height / 2).rounded()), withAttributes: attributes)
    }
}
