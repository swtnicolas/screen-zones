import AppKit

struct Tab {
    let id: CGWindowID
    let title: String
    let icon: NSImage?
    let active: Bool
    let minimized: Bool
}

enum TabButton: Int, CaseIterable {
    case close, minimize, fill
}

@MainActor
final class ZoneBar {
    static let height: CGFloat = 22
    static let sideWidth: CGFloat = 170
    static let narrowWidth: CGFloat = 30
    static let labelWidth: CGFloat = 26
    static let rowHeight: CGFloat = 22
    private static let openDelay = 0.15

    static func size(of side: Side, compact: Bool) -> CGFloat {
        side.vertical ? (compact ? narrowWidth : sideWidth) : height
    }

    static func label(of bar: CGRect, side: Side) -> CGRect {
        side.vertical
            ? CGRect(x: bar.minX, y: bar.minY, width: bar.width, height: rowHeight)
            : CGRect(x: bar.minX, y: bar.minY, width: labelWidth, height: bar.height)
    }

    private let panel: NSPanel
    private let view: BarView
    private var narrow = NSRect.zero
    private var wide = NSRect.zero
    private var expandable = false
    private var expanded = false
    private var raised = false
    private var timer: Timer?

    init(
        onSelect: @escaping (CGWindowID) -> Void,
        onDrag: @escaping (CGWindowID, NSPoint) -> Void,
        onDrop: @escaping (CGWindowID, NSPoint) -> Void,
        onReorder: @escaping (CGWindowID, Int) -> Void,
        onMenu: @escaping (CGWindowID) -> NSMenu?,
        onZoneMenu: @escaping () -> NSMenu?,
        onButton: @escaping (CGWindowID, TabButton) -> Void,
        onLabel: @escaping () -> Void
    ) {
        view = BarView()
        view.onSelect = onSelect
        view.onDrag = onDrag
        view.onDrop = onDrop
        view.onReorder = onReorder
        view.onMenu = onMenu
        view.onZoneMenu = onZoneMenu
        view.onButton = onButton
        view.onLabel = onLabel
        panel = FreePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.colorSpace = .sRGB
        panel.backgroundColor = BarView.background
        panel.isOpaque = true
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = view
        view.onHover = { [weak self] inside in self?.hover(inside) }
    }

    func show(
        label: String, tabs: [Tab], compact: Bool, side: Side, frame: NSRect, wide: NSRect, expandable: Bool,
        leftLine: Bool, topLine: Bool
    ) {
        narrow = frame
        self.wide = wide
        self.expandable = expandable
        if !expandable { expanded = false }
        view.label = label
        view.tabs = tabs
        view.compact = compact
        view.side = side
        view.leftLine = leftLine
        view.topLine = topLine
        apply()
    }

    func close() {
        timer?.invalidate()
        timer = nil
        panel.close()
    }

    private func apply() {
        let target = expanded ? wide : narrow
        if panel.frame != target { panel.setFrame(target, display: false) }
        view.updateTrackingAreas()
        view.needsDisplay = true
        if expanded {
            if !raised {
                panel.level = .floating
                panel.orderFrontRegardless()
            }
            raised = true
        } else if raised || !panel.isVisible {
            panel.level = .normal
            panel.orderBack(nil)
            raised = false
        }
    }

    private func hover(_ inside: Bool) {
        timer?.invalidate()
        timer = nil
        if inside {
            guard expandable, !expanded else { return }
            schedule(Self.openDelay) { [weak self] in
                self?.expanded = true
                self?.apply()
            }
        } else if expanded, !view.pressing {
            expanded = false
            apply()
        }
    }

    private func schedule(_ delay: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        let timer = Timer(timeInterval: delay, repeats: false) { _ in
            MainActor.assumeIsolated { action() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}

class FreePanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

private final class BarView: NSView {
    static let background = NSColor(srgbRed: 0.07, green: 0.11, blue: 0.22, alpha: 1)
    private static let tabColor = NSColor(srgbRed: 0.141, green: 0.2, blue: 0.31, alpha: 1)
    private static let activeColor = NSColor(srgbRed: 0.22, green: 0.42, blue: 0.82, alpha: 1)
    private static let maximumTab: CGFloat = 240
    private static let iconSize: CGFloat = 20
    private static let buttonColors = [
        NSColor(srgbRed: 1, green: 0.373, blue: 0.341, alpha: 1),
        NSColor(srgbRed: 0.996, green: 0.737, blue: 0.180, alpha: 1),
        NSColor(srgbRed: 0.157, green: 0.784, blue: 0.251, alpha: 1),
    ]
    private static let buttonSize: CGFloat = 12
    private static let buttonStep: CGFloat = 20
    private static let buttonInset: CGFloat = 8
    private static let buttonsWidth = buttonInset + buttonStep * 2 + buttonSize + 4

    private static let titleAttributes: [NSAttributedString.Key: Any] = {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        return [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor(srgbRed: 0.92, green: 0.92, blue: 0.92, alpha: 1),
            .paragraphStyle: style,
        ]
    }()

    private static let minimizedTitleAttributes = titleAttributes.merging(
        [.foregroundColor: NSColor(srgbRed: 0.55, green: 0.55, blue: 0.55, alpha: 1)]
    ) { $1 }

    private static let labelAttributes: [NSAttributedString.Key: Any] = {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        return [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor(srgbRed: 0.55, green: 0.62, blue: 0.76, alpha: 1),
            .paragraphStyle: style,
        ]
    }()

    var label = ""
    var tabs: [Tab] = []
    var compact = false
    var side = Side.top
    var leftLine = false
    var topLine = false
    var onSelect: ((CGWindowID) -> Void)?
    var onDrag: ((CGWindowID, NSPoint) -> Void)?
    var onDrop: ((CGWindowID, NSPoint) -> Void)?
    var onReorder: ((CGWindowID, Int) -> Void)?
    var onMenu: ((CGWindowID) -> NSMenu?)?
    var onZoneMenu: (() -> NSMenu?)?
    var onButton: ((CGWindowID, TabButton) -> Void)?
    var onLabel: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    private var pressed: (id: CGWindowID, start: NSPoint)?
    private var pressedButton: (id: CGWindowID, button: TabButton)?
    private var dragging = false
    private var hoveredIndex: Int?
    private var hoveredButtons: CGWindowID?
    private var barTracking: NSTrackingArea?

    var pressing: Bool { pressed != nil }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var vertical: Bool { side.vertical }
    private var labelExtent: CGFloat { vertical ? ZoneBar.rowHeight : ZoneBar.labelWidth }
    private var iconWidth: CGFloat { (vertical ? ZoneBar.rowHeight : bounds.height) + 6 }
    private var titled: Bool { !vertical || bounds.width - 2 > iconWidth }

    private func along(_ point: NSPoint) -> CGFloat {
        vertical ? point.y : point.x
    }

    private var slots: [ClosedRange<CGFloat>] {
        var start = labelExtent
        let active = tabs.map(\.active)
        let widths = vertical
            ? Geometry.tabWidths(active, compact: false, space: bounds.height - labelExtent, icon: iconWidth, maximum: ZoneBar.rowHeight + 2)
            : Geometry.tabWidths(active, compact: compact, space: bounds.width - labelExtent, icon: iconWidth, maximum: Self.maximumTab)
        return widths.map { width in
            defer { start += width }
            return start...(start + width)
        }
    }

    private func tabArea(of slot: ClosedRange<CGFloat>) -> NSRect {
        let length = slot.upperBound - slot.lowerBound
        if vertical {
            return NSRect(x: side == .right ? 2 : 0, y: slot.lowerBound, width: bounds.width - 2, height: length - 2)
        }
        return NSRect(x: slot.lowerBound, y: side == .bottom ? 2 : 0, width: length - 4, height: bounds.height - 2)
    }

    private func outward(_ area: NSRect) -> NSRect {
        switch side {
        case .top: NSRect(x: area.minX, y: area.minY - 4, width: area.width, height: area.height + 4)
        case .bottom: NSRect(x: area.minX, y: area.minY, width: area.width, height: area.height + 4)
        case .left: NSRect(x: area.minX - 4, y: area.minY, width: area.width + 4, height: area.height)
        case .right: NSRect(x: area.minX, y: area.minY, width: area.width + 4, height: area.height)
        }
    }

    private func textY(_ area: NSRect) -> CGFloat {
        (area.midY - 7.5).rounded()
    }

    override func draw(_ dirtyRect: NSRect) {
        Self.background.setFill()
        bounds.fill()
        let labelRect = vertical
            ? NSRect(x: 0, y: textY(NSRect(x: 0, y: 0, width: bounds.width, height: ZoneBar.rowHeight)), width: bounds.width, height: 16)
            : NSRect(x: 0, y: textY(NSRect(x: 0, y: side == .bottom ? 2 : 0, width: 0, height: bounds.height - 2)), width: ZoneBar.labelWidth, height: 16)
        (label as NSString).draw(in: labelRect, withAttributes: Self.labelAttributes)
        let buttons = shownButtons
        for (tab, slot) in zip(tabs, slots) {
            let area = tabArea(of: slot)
            (tab.active ? Self.activeColor : Self.tabColor).setFill()
            NSBezierPath(roundedRect: outward(area), xRadius: 4, yRadius: 4).fill()
            var trail: CGFloat = 0
            if let group = buttons.first(where: { $0.id == tab.id }) {
                drawButtons(group.rects, pressed: pressedButton?.id == tab.id ? pressedButton?.button : nil, symbols: hoveredButtons == tab.id)
                trail = Self.buttonsWidth
            }
            let showsTitle = hasTitle(tab)
            let iconSize = min(Self.iconSize, area.width - 4, area.height)
            let iconX = vertical && !showsTitle ? (area.midX - iconSize / 2).rounded() : area.minX + 2
            let icon = NSRect(x: iconX, y: (area.midY - iconSize / 2).rounded(), width: iconSize, height: iconSize)
            tab.icon?.draw(in: icon, from: .zero, operation: .sourceOver, fraction: tab.minimized ? 0.4 : 1, respectFlipped: true, hints: nil)
            guard showsTitle else { continue }
            let titleX = icon.maxX + 2
            (tab.title as NSString).draw(
                with: NSRect(x: titleX, y: textY(area), width: max(0, area.maxX - 4 - trail - titleX), height: 16),
                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                attributes: tab.minimized ? Self.minimizedTitleAttributes : Self.titleAttributes
            )
        }
        ZoneBorders.color.setFill()
        if leftLine { NSRect(x: 0, y: 0, width: ZoneManager.lineWidth, height: bounds.height).fill() }
        if topLine { NSRect(x: 0, y: 0, width: bounds.width, height: ZoneManager.lineWidth).fill() }
    }

    private func hasTitle(_ tab: Tab) -> Bool {
        vertical ? titled : !compact || tab.active
    }

    private var shownButtons: [(id: CGWindowID, rects: [NSRect])] {
        let slots = self.slots
        var indices = tabs.indices.filter { tabs[$0].active }
        if let hoveredIndex, !indices.contains(hoveredIndex) { indices.append(hoveredIndex) }
        return indices.compactMap { index in
            guard slots.indices.contains(index), tabs.indices.contains(index), !tabs[index].minimized, hasTitle(tabs[index]) else { return nil }
            let area = tabArea(of: slots[index])
            guard area.width >= Self.buttonsWidth + iconWidth - 4 else { return nil }
            let y = (area.midY - Self.buttonSize / 2).rounded()
            let first = area.maxX - Self.buttonInset - Self.buttonStep * 2 - Self.buttonSize
            return (tabs[index].id, TabButton.allCases.map { button in
                NSRect(x: first + CGFloat(button.rawValue) * Self.buttonStep, y: y, width: Self.buttonSize, height: Self.buttonSize)
            })
        }
    }

    private func button(at point: NSPoint) -> (id: CGWindowID, button: TabButton)? {
        for group in shownButtons {
            if let index = group.rects.firstIndex(where: { $0.insetBy(dx: -3, dy: -3).contains(point) }) {
                return (group.id, TabButton.allCases[index])
            }
        }
        return nil
    }

    private func drawButtons(_ rects: [NSRect], pressed: TabButton?, symbols: Bool) {
        for (button, rect) in zip(TabButton.allCases, rects) {
            let color = Self.buttonColors[button.rawValue]
            (button == pressed ? color.blended(withFraction: 0.25, of: .black) ?? color : color).setFill()
            NSBezierPath(ovalIn: rect).fill()
            guard symbols else { continue }
            let mid = NSPoint(x: rect.midX, y: rect.midY)
            NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.5).set()
            let path = NSBezierPath()
            path.lineWidth = 1.2
            path.lineCapStyle = .round
            switch button {
            case .close:
                path.move(to: NSPoint(x: mid.x - 2.5, y: mid.y - 2.5)); path.line(to: NSPoint(x: mid.x + 2.5, y: mid.y + 2.5))
                path.move(to: NSPoint(x: mid.x - 2.5, y: mid.y + 2.5)); path.line(to: NSPoint(x: mid.x + 2.5, y: mid.y - 2.5))
                path.stroke()
            case .minimize:
                path.move(to: NSPoint(x: mid.x - 3, y: mid.y)); path.line(to: NSPoint(x: mid.x + 3, y: mid.y))
                path.stroke()
            case .fill:
                path.move(to: NSPoint(x: mid.x - 3, y: mid.y - 3)); path.line(to: NSPoint(x: mid.x + 1, y: mid.y - 3)); path.line(to: NSPoint(x: mid.x - 3, y: mid.y + 1)); path.close()
                path.move(to: NSPoint(x: mid.x + 3, y: mid.y + 3)); path.line(to: NSPoint(x: mid.x - 1, y: mid.y + 3)); path.line(to: NSPoint(x: mid.x + 3, y: mid.y - 1)); path.close()
                path.fill()
            }
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if barTracking == nil {
            let tracking = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self)
            addTrackingArea(tracking)
            barTracking = tracking
        }
        trackHover()
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?(true)
        trackHover()
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(false)
        trackHover()
    }

    override func mouseMoved(with event: NSEvent) {
        trackHover()
    }

    private func trackHover() {
        let point = window.map { convert($0.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil) }
        let index: Int? = point.flatMap { point in
            guard pressed == nil, bounds.contains(point), along(point) >= labelExtent else { return nil }
            let at = along(point)
            return slots.firstIndex { $0.contains(at) }
        }
        let previous = (hoveredIndex, hoveredButtons)
        hoveredIndex = index
        hoveredButtons = index == nil ? nil : point.flatMap { point in
            shownButtons.first { $0.rects.reduce(NSRect.null) { $0.union($1) }.insetBy(dx: -3, dy: -3).contains(point) }?.id
        }
        if previous.0 != hoveredIndex || previous.1 != hoveredButtons { needsDisplay = true }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        if along(point) >= labelExtent, let id = tab(at: point) { return onMenu?(id) }
        return onZoneMenu?()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        dragging = false
        if let hit = button(at: point) {
            pressedButton = hit
            pressed = nil
            needsDisplay = true
            return
        }
        if along(point) < labelExtent {
            pressed = nil
            onLabel?()
            return
        }
        pressed = tab(at: point).map { ($0, NSEvent.mouseLocation) }
    }

    override func mouseDragged(with event: NSEvent) {
        trackHover()
        guard let pressed else { return }
        let location = NSEvent.mouseLocation
        if !dragging, hypot(location.x - pressed.start.x, location.y - pressed.start.y) < 4 { return }
        dragging = true
        if let window, window.frame.contains(location) {
            onReorder?(pressed.id, slot(at: convert(window.convertPoint(fromScreen: location), from: nil)))
        } else {
            onDrag?(pressed.id, location)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if let pressedButton {
            self.pressedButton = nil
            needsDisplay = true
            if let hit = button(at: convert(event.locationInWindow, from: nil)), hit.id == pressedButton.id, hit.button == pressedButton.button {
                onButton?(hit.id, hit.button)
            }
            return
        }
        guard let pressed else { return }
        self.pressed = nil
        if dragging {
            let location = NSEvent.mouseLocation
            if window?.frame.contains(location) != true { onDrop?(pressed.id, location) }
        } else {
            onSelect?(pressed.id)
        }
        dragging = false
        if !bounds.contains(convert(event.locationInWindow, from: nil)) { onHover?(false) }
        trackHover()
    }

    private func slot(at point: NSPoint) -> Int {
        let slots = self.slots
        let at = along(point)
        guard let last = slots.last else { return 0 }
        if at >= last.upperBound { return slots.count - 1 }
        return slots.firstIndex { at < $0.upperBound } ?? 0
    }

    private func tab(at point: NSPoint) -> CGWindowID? {
        let at = along(point)
        return slots.firstIndex { $0.contains(at) }.map { tabs[$0].id }
    }
}

@MainActor
final class Ghost {
    private var panel: NSPanel?

    func show(_ frame: NSRect) {
        let panel = self.panel ?? make()
        self.panel = panel
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.close()
        panel = nil
    }

    private func make() -> NSPanel {
        let panel = FreePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.colorSpace = .sRGB
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = CGColor(srgbRed: 0.22, green: 0.42, blue: 0.82, alpha: 0.25)
        view.layer?.borderColor = CGColor(srgbRed: 0.22, green: 0.42, blue: 0.82, alpha: 0.9)
        view.layer?.borderWidth = 3
        view.layer?.cornerRadius = 6
        panel.contentView = view
        return panel
    }
}

@MainActor
final class SizeBadge {
    private var panel: FreePanel?
    private let view = BadgeView()

    func show(_ lines: [(label: String, value: String)], placing origin: (NSSize) -> NSPoint) {
        let panel = self.panel ?? make()
        self.panel = panel
        view.lines = lines
        let size = view.size
        panel.setFrame(NSRect(origin: origin(size), size: size), display: true)
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func make() -> FreePanel {
        let panel = FreePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.colorSpace = .sRGB
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.contentView = view
        return panel
    }
}

private final class BadgeView: NSView {
    private static let fill = NSColor(srgbRed: 0.08, green: 0.09, blue: 0.14, alpha: 0.94)
    private static let stroke = NSColor(srgbRed: 0.36, green: 0.36, blue: 0.40, alpha: 1)
    private static let labelAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 13),
        .foregroundColor: NSColor(srgbRed: 0.62, green: 0.70, blue: 0.85, alpha: 1),
    ]
    private static let valueAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular),
        .foregroundColor: NSColor(srgbRed: 0.93, green: 0.93, blue: 0.93, alpha: 1),
    ]
    private static let padding = NSSize(width: 12, height: 8)
    private static let lineHeight: CGFloat = 19
    private static let gap: CGFloat = 14

    var lines: [(label: String, value: String)] = [] {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    private var columns: (label: CGFloat, value: CGFloat) {
        let label = lines.map { ($0.label as NSString).size(withAttributes: Self.labelAttributes).width }.max() ?? 0
        let value = lines.map { ($0.value as NSString).size(withAttributes: Self.valueAttributes).width }.max() ?? 0
        return (label.rounded(.up), value.rounded(.up))
    }

    var size: NSSize {
        let columns = self.columns
        return NSSize(
            width: Self.padding.width * 2 + columns.label + Self.gap + columns.value,
            height: Self.padding.height * 2 + Self.lineHeight * CGFloat(lines.count)
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        Self.fill.setFill()
        path.fill()
        Self.stroke.setStroke()
        path.lineWidth = 1
        path.stroke()
        let columns = self.columns
        let right = Self.padding.width + columns.label + Self.gap + columns.value
        for (index, line) in lines.enumerated() {
            let y = Self.padding.height + CGFloat(index) * Self.lineHeight + 1
            (line.label as NSString).draw(at: NSPoint(x: Self.padding.width, y: y), withAttributes: Self.labelAttributes)
            let value = line.value as NSString
            let width = value.size(withAttributes: Self.valueAttributes).width
            value.draw(at: NSPoint(x: (right - width).rounded(), y: y), withAttributes: Self.valueAttributes)
        }
    }
}

@MainActor
final class ZoneBorders {
    static let color = NSColor(srgbRed: 0.42, green: 0.42, blue: 0.42, alpha: 1)

    private var panels: [FreePanel] = []
    private var shown: [NSRect] = []

    func show(_ frames: [NSRect]) {
        guard frames != shown else { return }
        shown = frames
        while panels.count < frames.count {
            panels.append(make())
        }
        while panels.count > frames.count {
            panels.removeLast().close()
        }
        for (panel, frame) in zip(panels, frames) {
            panel.setFrame(frame, display: false)
            if !panel.isVisible { panel.orderBack(nil) }
        }
    }

    func hide() {
        for panel in panels {
            panel.close()
        }
        panels.removeAll()
        shown = []
    }

    private func make() -> FreePanel {
        let panel = FreePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.colorSpace = .sRGB
        panel.backgroundColor = Self.color
        panel.isOpaque = true
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        return panel
    }
}
