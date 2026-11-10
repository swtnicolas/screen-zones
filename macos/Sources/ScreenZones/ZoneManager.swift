import AppKit
import ApplicationServices

private struct Delivered: @unchecked Sendable {
    let element: AXUIElement
}

private let observerCallback: AXObserverCallback = { _, element, notification, refcon in
    guard let refcon else { return }
    let manager = Unmanaged<ZoneManager>.fromOpaque(refcon).takeUnretainedValue()
    let name = notification as String
    let delivered = Delivered(element: element)
    MainActor.assumeIsolated { manager.handle(name, delivered.element) }
}

struct ManagedDisplay {
    let uuid: String
    let name: String
    let enabled: Bool
}

@MainActor
final class ZoneManager: MouseHandler {
    private struct Tracked {
        let element: AXUIElement
        let pid: pid_t
        var display: String
        var zone: String
        var known: CGRect?
        var filled = false
        var restore: CGRect?
        var minimum: CGSize?
        var preferred: CGSize?
        var title: String
        var order: Int
        var minimized = false
        var nativeFullScreen = false
    }

    private struct Surface {
        let uuid: String
        let screen: NSScreen
        let area: CGRect
        let bounds: CGRect
        let others: [CGRect]
        let placed: [PlacedZone]
    }

    private enum Fit {
        case keep, arrive, fill, free
    }

    private struct Carry {
        let element: AXUIElement
        let start: CGPoint?
        let grip: CGPoint?
    }

    static let lineWidth: CGFloat = 1
    static let defaultZone = "A"
    static let carryInterval = 1.0 / 60

    let store: Store
    var onStateChange: (() -> Void)?
    var onTabMenu: ((_ id: CGWindowID, _ bundle: String?, _ name: String) -> NSMenu?)?
    var onZoneMenu: ((_ display: String, _ zone: String) -> NSMenu?)?
    private(set) var running = false
    private(set) var paused = false

    private var tracked: [CGWindowID: Tracked] = [:]
    private var saved: [String: SavedWindow] = [:]
    private var observers: [pid_t: AppObserver] = [:]
    private var launches: NSKeyValueObservation?
    private var promotions: [pid_t: (app: NSRunningApplication, observation: NSKeyValueObservation)] = [:]
    private var icons: [pid_t: NSImage] = [:]
    private var surfaces: [String: Surface] = [:]
    private var counter = 0
    private var bars: [String: ZoneBar] = [:]
    private let ghost = Ghost()
    private let badge = SizeBadge()
    private var zoneInfo: String?
    private let borders = ZoneBorders()
    private var editor: ZoneEditor?
    private var ghostKey: String?
    private let tap = MouseTap()
    private let systemWide = AXUIElementCreateSystemWide()
    private let ownPID = getpid()
    private var redrawTimer: Timer?
    private var saveTimer: Timer?
    private var holdTimer: Timer?
    private var holdUntil: TimeInterval = 0
    private var settleTimer: Timer?
    private var gesture: [AXUIElement] = []
    private var gestureOnSurface = false
    private var mouseIsDown = false
    private var downAt: TimeInterval = 0
    private var upAt: TimeInterval = 0
    private var downPoint: CGPoint?
    private var upPoint: CGPoint?
    private var pressedFrames: [CGWindowID: CGRect] = [:]
    private var resizedWhileDown: Set<CGWindowID> = []
    private var carry: Carry?
    private var carryPoint: CGPoint?
    private var carryTimer: Timer?
    private var zooming: AXUIElement?
    private var swallowUp = false
    private var doubleClick = false

    init(store: Store) {
        self.store = store
    }

    func start() {
        guard !running else { return }
        running = true
        saved = store.windows
        AXUIElementSetMessagingTimeout(systemWide, 1)
        refreshGeometry()
        tap.handler = self
        _ = tap.start()
        observeWorkspace()
        for app in NSWorkspace.shared.runningApplications {
            observe(app, launched: false)
        }
        scheduleRedraw()
        scheduleSave()
        onStateChange?()
    }

    func handle(_ name: String, _ element: AXUIElement) {
        guard running, !paused else { return }
        switch name {
        case kAXWindowCreatedNotification: windowCreated(element, retry: true)
        case kAXWindowMovedNotification, kAXWindowResizedNotification: windowChanged(element)
        case kAXUIElementDestroyedNotification: windowDestroyed(element)
        case kAXTitleChangedNotification: titleChanged(element)
        case kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification:
            if let id = trackedID(element) { tracked[id]?.minimized = name == kAXWindowMiniaturizedNotification }
            scheduleRedraw()
        default:
            scheduleRedraw()
        }
    }

    var menuDisplays: [ManagedDisplay] {
        Displays.active().enumerated().compactMap { index, id in
            guard let uuid = Displays.uuid(id) else { return nil }
            return ManagedDisplay(uuid: uuid, name: Displays.name(of: id) ?? "Pantalla \(index + 1)", enabled: store.displays[uuid] != nil)
        }
    }

    var managedDisplays: [ManagedDisplay] {
        menuDisplays.filter(\.enabled)
    }

    func setEnabled(_ enabled: Bool, display: ManagedDisplay) {
        if enabled {
            store.enable(display.uuid)
        } else {
            store.disable(display.uuid)
            tracked = tracked.filter { $0.value.display != display.uuid }
        }
        refreshGeometry()
        adoptAll(applyRules: enabled)
        scheduleRedraw()
    }

    func setLayout(_ name: String, on uuid: String) {
        store.choose(name, on: uuid)
        reflow()
    }

    func createLayout(named name: String, on uuid: String) {
        openEditor(on: uuid, title: name, zones: Layout.single.zones) { [weak self] zones in
            guard let self else { return }
            store.choose(store.add(Layout(name: name, zones: zones)), on: uuid)
        }
    }

    func editZones(on uuid: String) {
        guard let layout = store.layout(of: uuid), layout.name != Layout.single.name else { return }
        let title = store.hasDraft(uuid) ? "\(layout.name) (sin guardar)" : layout.name
        openEditor(on: uuid, title: title, zones: store.zones(of: uuid)) { [weak self] zones in
            self?.store.setZones(zones, of: layout.name)
        }
    }

    func discardChanges(on uuid: String) {
        store.discardDraft(on: uuid)
        reflow()
    }

    func removeLayout(_ name: String) {
        store.remove(name)
        reflow()
    }

    private func openEditor(on uuid: String, title: String, zones: [Zone], onSave: @escaping ([Zone]) -> Void) {
        guard let surface = surfaces[uuid] else { return }
        editor?.close()
        editor = ZoneEditor(
            title: title, zones: zones, frame: flip(surface.area), panelScale: panelScale(surface),
            onSave: { [weak self] zones in
                onSave(zones)
                self?.reflow()
            },
            onClose: { [weak self] in self?.editor = nil }
        )
    }

    func setPaused(_ value: Bool) {
        paused = value
        if value {
            tap.stop()
            stopCarry()
            hideGhost()
            hideBadge()
            closeBars()
        } else {
            _ = tap.start()
            refreshGeometry()
            adoptAll(applyRules: false)
            reflow()
        }
        onStateChange?()
    }

    func rule(for bundle: String) -> Rule? {
        store.rules[bundle]
    }

    func setRule(_ rule: Rule?, bundle: String) {
        var rules = store.rules
        rules[bundle] = rule
        store.rules = rules
        let wasFree = store.free.remove(bundle) != nil
        for observer in observers.values where observer.bundleID == bundle {
            if let rule, let target = resolve(rule) {
                for window in observer.element.windows where window.isStandardWindow {
                    adopt(window, pid: observer.pid, display: target.display, zone: target.zone, fit: .arrive)
                }
            } else if wasFree {
                for window in observer.element.windows {
                    adoptExisting(window, pid: observer.pid, applyRules: false)
                }
            }
        }
    }

    func setFree(bundle: String) {
        var rules = store.rules
        rules[bundle] = nil
        store.rules = rules
        store.free.insert(bundle)
        for (id, window) in tracked where observers[window.pid]?.bundleID == bundle {
            release(id)
        }
    }

    func setTabsAt(_ side: Side) {
        store.tabsAt = side
        reflow()
    }

    func setSide(_ side: Side?, on uuid: String) {
        store.setSide(side, on: uuid)
        reflow()
    }

    func setSide(_ side: Side?, ofZone id: String, on uuid: String) {
        store.setSide(side, ofZone: id, on: uuid)
        reflow()
    }

    func zoneIDs(of uuid: String) -> [String] {
        surfaces[uuid]?.placed.map(\.id) ?? []
    }

    func zone(of id: CGWindowID) -> (display: String, zone: String)? {
        guard let window = tracked[id], let (_, zone) = placement(of: id) else { return nil }
        return (window.display, zone.id)
    }

    func center(_ id: CGWindowID) {
        guard let window = tracked[id], let (surface, zone) = placement(of: id), let frame = window.element.frame else { return }
        window.element.setOrigin(Geometry.center(frame, in: zone.content, area: surface.area, side: zone.side).origin)
        place(id, .free)
        window.element.focus()
    }

    func isFilled(_ id: CGWindowID) -> Bool {
        tracked[id]?.filled ?? false
    }

    func toggleFill(_ id: CGWindowID) {
        guard let element = tracked[id]?.element else { return }
        toggleFill(element)
        element.focus()
    }

    func minimize(_ id: CGWindowID) {
        tracked[id]?.element.setMinimized(true)
    }

    func close(_ id: CGWindowID) {
        guard let element = tracked[id]?.element else { return }
        element.focus()
        element.press(kAXCloseButtonAttribute)
    }

    private func press(_ button: TabButton, on id: CGWindowID) {
        switch button {
        case .close: close(id)
        case .minimize: minimize(id)
        case .fill: toggleFill(id)
        }
    }

    private func tabMenu(_ id: CGWindowID) -> NSMenu? {
        guard let pid = tracked[id]?.pid else { return nil }
        let app = NSRunningApplication(processIdentifier: pid)
        return onTabMenu?(id, app?.bundleIdentifier, app?.localizedName ?? app?.bundleIdentifier ?? "")
    }

    private func isFree(pid: pid_t) -> Bool {
        observers[pid]?.bundleID.map(store.free.contains) ?? false
    }

    private func scheduleSave() {
        guard saveTimer == nil else { return }
        saveTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveWindows() }
        }
    }

    func saveWindows() {
        saveTimer?.invalidate()
        saveTimer = nil
        store.windows = tracked.reduce(into: saved.filter { NSRunningApplication(processIdentifier: $0.value.pid) != nil }) { windows, entry in
            let window = entry.value
            guard let size = window.preferred else { return }
            windows[String(entry.key)] = SavedWindow(
                pid: window.pid, display: window.display, zone: window.zone, width: size.width, height: size.height, filled: window.filled
            )
        }
    }

    private func hold() {
        holdUntil = ProcessInfo.processInfo.systemUptime + 3
        holdTimer?.invalidate()
        holdTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.running, !self.paused else { return }
                self.holdTimer = nil
                self.reflow()
                self.adoptAll(applyRules: false)
            }
        }
    }

    private func resolve(_ rule: Rule) -> (display: String, zone: String)? {
        if let display = rule.display {
            return surfaces[display] == nil ? nil : (display, rule.zone)
        }
        let ordered = orderedSurfaces
        guard let surface = ordered.first(where: { $0.placed.contains { $0.id == rule.zone } }) ?? ordered.first else { return nil }
        return (surface.uuid, rule.zone)
    }

    private func rule(forPID pid: pid_t) -> (display: String, zone: String)? {
        guard let bundle = observers[pid]?.bundleID, let rule = store.rules[bundle] else { return nil }
        return resolve(rule)
    }

    private var displaySet: String {
        surfaces.keys.sorted().joined(separator: " ")
    }

    private func lastZone(forPID pid: pid_t, at point: CGPoint) -> (display: String, zone: String)? {
        guard let bundle = observers[pid]?.bundleID, let last = store.lastZones[displaySet]?[bundle] else { return nil }
        return resolve(last) ?? surface(at: point).map { ($0.uuid, last.zone) }
    }

    private func recordZone(_ id: CGWindowID) {
        guard ProcessInfo.processInfo.systemUptime >= holdUntil, let window = tracked[id],
              let bundle = observers[window.pid]?.bundleID else { return }
        let last = Rule(display: window.display, zone: window.zone)
        var zones = store.lastZones
        guard zones[displaySet]?[bundle] != last else { return }
        zones[displaySet, default: [:]][bundle] = last
        store.lastZones = zones
    }

    private var orderedSurfaces: [Surface] {
        surfaces.values.sorted { $0.bounds.minX < $1.bounds.minX }
    }

    private var top: CGFloat {
        NSScreen.screens.first?.frame.maxY ?? 0
    }

    private func global(_ point: NSPoint) -> CGPoint {
        CGPoint(x: point.x, y: top - point.y)
    }

    private func focusedWindow() -> (AXUIElement, pid_t)? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let window = observers[pid]?.element.focusedWindow else { return nil }
        return (window, pid)
    }

    private var refcon: UnsafeMutableRawPointer { Unmanaged.passUnretained(self).toOpaque() }

    private func observeWorkspace() {
        launches = NSWorkspace.shared.observe(\.runningApplications, options: [.new, .old]) { [weak self] _, change in
            let launched = change.newValue ?? [], terminated = change.oldValue ?? []
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    for app in terminated { self?.forget(app.processIdentifier) }
                    for app in launched where app.activationPolicy != .regular { self?.observe(app, launched: true) }
                }
            }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { self?.observe(app, launched: true) }
        }
        workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { self?.activated(app) }
        }
        for name in [NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleRedraw() }
            }
        }
        workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.spaceChanged() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
    }

    private func activated(_ app: NSRunningApplication) {
        scheduleRedraw()
    }

    private func spaceChanged() {
        guard !paused else { return }
        adoptVisible()
        takeFullScreenWindows()
        after(1) { [weak self] in self?.takeFullScreenWindows() }
        scheduleRedraw()
    }

    private func takeFullScreenWindows() {
        let showing = Displays.showingFullScreen()
        guard running, !paused, !showing.isEmpty else { return }
        for (id, window) in tracked where showing.contains(window.display) && !window.nativeFullScreen && window.element.isFullScreen {
            enteredFullScreen(id)
        }
    }

    private func screensChanged() {
        guard running, !paused else { return }
        hold()
        refreshGeometry()
        scheduleRedraw()
        after(1) { [weak self] in
            guard let self, self.running, !self.paused else { return }
            self.reflow()
            self.adoptAll(applyRules: false)
        }
    }

    private func observe(_ app: NSRunningApplication, launched: Bool) {
        let pid = app.processIdentifier
        guard pid != ownPID, observers[pid] == nil else { return }
        guard app.activationPolicy == .regular else {
            if promotions[pid] == nil, !app.isTerminated { watchPromotion(of: app) }
            return
        }
        promotions.removeValue(forKey: pid)?.observation.invalidate()
        guard let observer = AppObserver(app, refcon: refcon, callback: observerCallback) else { return }
        observers[pid] = observer
        subscribe(observer, launched: launched, attempt: 0)
    }

    private func watchPromotion(of app: NSRunningApplication) {
        let observation = app.observe(\.activationPolicy) { [weak self] app, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.observe(app, launched: true) }
            }
        }
        promotions[app.processIdentifier] = (app, observation)
    }

    private func subscribe(_ observer: AppObserver, launched: Bool, attempt: Int) {
        guard observers[observer.pid] === observer else { return }
        guard observer.subscribeApp() else {
            if attempt < 20 {
                after(0.25) { [weak self] in self?.subscribe(observer, launched: launched, attempt: attempt + 1) }
            }
            return
        }
        guard !paused else { return }
        for window in observer.element.windows {
            if launched {
                windowCreated(window, retry: false)
            } else {
                adoptExisting(window, pid: observer.pid, applyRules: true)
            }
        }
    }

    private func forget(_ pid: pid_t) {
        observers.removeValue(forKey: pid)?.stop()
        promotions.removeValue(forKey: pid)?.observation.invalidate()
        icons[pid] = nil
        tracked = tracked.filter { $0.value.pid != pid }
        scheduleRedraw()
        scheduleSave()
    }

    private func adoptAll(applyRules: Bool) {
        for observer in observers.values {
            for window in observer.element.windows {
                adoptExisting(window, pid: observer.pid, applyRules: applyRules)
            }
        }
    }

    private func adoptVisible() {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as NSArray? else { return }
        var pids = Set<pid_t>()
        for case let info as NSDictionary in list {
            guard let number = info["kCGWindowNumber"] as? NSNumber, tracked[number.uint32Value] == nil,
                  (info["kCGWindowLayer"] as? NSNumber)?.intValue == 0,
                  let pid = (info["kCGWindowOwnerPID"] as? NSNumber)?.int32Value, observers[pid] != nil,
                  let rectInfo = info["kCGWindowBounds"] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: rectInfo as CFDictionary),
                  surface(at: rect.center) != nil else { continue }
            pids.insert(pid)
        }
        for pid in pids {
            for window in observers[pid]?.element.windows ?? [] {
                adoptExisting(window, pid: pid, applyRules: false)
            }
        }
    }

    private func surface(at point: CGPoint) -> Surface? {
        surfaces.values.first { $0.bounds.contains(point) }
    }

    private func adoptExisting(_ window: AXUIElement, pid: pid_t, applyRules: Bool) {
        guard window.isStandardWindow || window.isMinimized, let id = window.windowID, tracked[id] == nil, let frame = window.frame else { return }
        let rule = rule(forPID: pid)
        if let surface = surface(at: frame.center) {
            let ruled = rule?.display == surface.uuid ? rule?.zone : nil
            let zone = ruled ?? surface.placed.zone(at: frame.center)?.id ?? Self.defaultZone
            adopt(window, pid: pid, display: surface.uuid, zone: zone, fit: .arrive)
        } else if applyRules, let rule {
            adopt(window, pid: pid, display: rule.display, zone: rule.zone, fit: .arrive)
        }
    }

    private func windowCreated(_ element: AXUIElement, retry: Bool) {
        guard let pid = element.pid, pid != ownPID else { return }
        guard element.isStandardWindow else {
            if retry {
                after(0.2) { [weak self] in self?.windowCreated(element, retry: false) }
            }
            return
        }
        guard let frame = element.frame else { return }
        if let target = rule(forPID: pid) ?? lastZone(forPID: pid, at: frame.center) {
            adopt(element, pid: pid, display: target.display, zone: target.zone, fit: .arrive)
        } else if let surface = surface(at: frame.center) {
            adopt(element, pid: pid, display: surface.uuid, zone: Self.defaultZone, fit: .arrive)
        }
    }

    private func windowChanged(_ element: AXUIElement) {
        if let carry, CFEqual(carry.element, element) { return }
        if inGesture {
            if mouseIsDown, let id = trackedID(element) {
                let frame = serverFrame(of: id)
                if let start = pressedFrames[id], let frame, Geometry.gesture(from: start, to: frame) == .resized {
                    resizedWhileDown.insert(id)
                }
                showSize(id, frame)
            }
            remember(element)
            return
        }
        guard let frame = element.frame else { return }
        if let id = trackedID(element), let window = tracked[id] {
            let home = surfaces[window.display]
            let covering = covers(frame, display: window.display)
            if window.nativeFullScreen, !covering { tracked[id]?.nativeFullScreen = false }
            if covering, element.isFullScreen {
                enteredFullScreen(id)
                return
            }
            if let known = window.known, Geometry.same(frame, known) { return }
            if ProcessInfo.processInfo.systemUptime < holdUntil { return }
            if home?.bounds.contains(frame.center) == true {
                place(id, .free)
            } else if let other = surface(at: frame.center) {
                tracked[id]?.display = other.uuid
                tracked[id]?.zone = other.placed.zone(at: frame.center)?.id ?? Self.defaultZone
                recordZone(id)
                place(id, .free)
                scheduleRedraw()
            } else {
                release(id)
            }
        } else if let surface = surface(at: frame.center), let pid = element.pid, pid != ownPID, element.isStandardWindow {
            adopt(element, pid: pid, display: surface.uuid, zone: surface.placed.zone(at: frame.center)?.id ?? Self.defaultZone, fit: .arrive)
        }
    }

    private func covers(_ frame: CGRect, display: String) -> Bool {
        guard let area = surfaces[display]?.area else { return false }
        return frame.insetBy(dx: -Geometry.pixelTolerance, dy: -Geometry.pixelTolerance).contains(area)
    }

    private func enteredFullScreen(_ id: CGWindowID) {
        guard tracked[id]?.nativeFullScreen == false else { return }
        tracked[id]?.nativeFullScreen = true
        scheduleRedraw()
    }

    private func windowDestroyed(_ element: AXUIElement) {
        gesture.removeAll { CFEqual($0, element) }
        if let id = trackedID(element) { release(id) }
    }

    private func titleChanged(_ element: AXUIElement) {
        guard let id = trackedID(element) else { return }
        tracked[id]?.title = element.title
        scheduleRedraw()
    }

    private func trackedID(_ element: AXUIElement) -> CGWindowID? {
        tracked.first { CFEqual($0.value.element, element) }?.key
    }

    private func placement(of id: CGWindowID) -> (Surface, PlacedZone)? {
        guard let window = tracked[id], let surface = surfaces[window.display],
              let zone = surface.placed.resolve(window.zone) ?? surface.placed.resolve(Self.defaultZone) ?? surface.placed.first else { return nil }
        return (surface, zone)
    }

    private func adopt(_ element: AXUIElement, pid: pid_t, display: String, zone: String, fit: Fit) {
        guard !isFree(pid: pid), let id = element.windowID else { return }
        var fit = fit
        if tracked[id] == nil {
            counter += 1
            let restored = saved.removeValue(forKey: String(id)).flatMap { $0.pid == pid ? $0 : nil }
            let home = restored.flatMap { store.displays[$0.display] == nil ? nil : $0 }
            if home != nil { fit = .keep }
            tracked[id] = Tracked(
                element: element, pid: pid, display: home?.display ?? display, zone: home?.zone ?? zone, filled: restored?.filled ?? false,
                preferred: restored.map { CGSize(width: $0.width, height: $0.height) }, title: element.title, order: counter,
                minimized: element.isMinimized
            )
            observers[pid]?.subscribe(window: element)
        } else {
            tracked[id]?.display = display
            tracked[id]?.zone = zone
        }
        recordZone(id)
        place(id, fit)
        scheduleRedraw()
    }

    private func release(_ id: CGWindowID) {
        tracked[id] = nil
        scheduleRedraw()
        scheduleSave()
    }

    private func place(_ id: CGWindowID, _ fit: Fit = .keep) {
        guard let window = tracked[id], !window.nativeFullScreen, let (surface, zone) = placement(of: id),
              let frame = window.element.frame else { return }
        if covers(frame, display: window.display), window.element.isFullScreen {
            enteredFullScreen(id)
            return
        }
        let content = zone.content
        let filling = fit == .fill || (fit != .free && window.filled)
        let arriving = fit == .arrive && !content.contains(frame.center)
        let minimum = window.minimum ?? .zero
        let preferred = fit == .free ? frame.size : window.preferred ?? frame.size
        let size = CGSize(
            width: max(min(preferred.width, content.width), minimum.width),
            height: max(min(preferred.height, content.height), minimum.height)
        )
        let attempt = filling
            ? content
            : arriving
                ? Geometry.arrive(CGRect(origin: frame.origin, size: size), in: content, area: surface.area, side: zone.side)
                : CGRect(origin: frame.origin, size: size)
        var result = frame
        if !Geometry.same(frame, attempt) {
            if filling || arriving { window.element.setFrame(attempt) } else { window.element.setSize(size) }
            result = window.element.frame ?? attempt
            if let retry = Geometry.retry(attempt.size, got: result.size) {
                window.element.setSize(retry)
                result = window.element.frame ?? result
            }
            var refused = minimum
            if result.width > attempt.width + Geometry.pixelTolerance { refused.width = result.width }
            if result.height > attempt.height + Geometry.pixelTolerance { refused.height = result.height }
            if refused != minimum { tracked[id]?.minimum = refused }
        }
        let start = CGRect(origin: filling || arriving ? result.origin : frame.origin, size: result.size)
        let walls = Geometry.walls(content, bounds: surface.bounds, others: surface.others)
        let target = fit == .free && !store.snap
            ? Geometry.contain(start, in: content, area: surface.area, side: zone.side, walls: walls)
            : Geometry.arrive(start, in: content, area: surface.area, centering: arriving, side: zone.side)
        if abs(target.minX - result.minX) > Geometry.pixelTolerance || abs(target.minY - result.minY) > Geometry.pixelTolerance {
            window.element.setOrigin(target.origin)
            result = window.element.frame ?? target
        }
        let resized = window.known.map {
            abs($0.width - frame.width) > Geometry.pixelTolerance || abs($0.height - frame.height) > Geometry.pixelTolerance
        } ?? true
        if fit == .free && resized {
            tracked[id]?.preferred = result.size
        } else if window.preferred == nil {
            tracked[id]?.preferred = preferred
        }
        tracked[id]?.known = result
        tracked[id]?.filled = Geometry.same(result, content)
        scheduleSave()
    }

    private func toggleFill(_ element: AXUIElement, from frame: CGRect? = nil) {
        guard let id = trackedID(element) ?? element.windowID, let window = tracked[id],
              let frame = frame ?? element.frame, let (surface, zone) = placement(of: id) else { return }
        if window.filled {
            let size = CGSize(width: (zone.content.width * 0.7).rounded(), height: (zone.content.height * 0.7).rounded())
            let restore = window.restore ?? Geometry.arrive(CGRect(origin: .zero, size: size), in: zone.content, area: surface.area, side: zone.side)
            tracked[id]?.restore = nil
            element.setFrame(restore)
            place(id, .free)
        } else {
            tracked[id]?.restore = frame
            place(id, .fill)
        }
        element.focus()
        scheduleRedraw()
    }

    private func reflow() {
        refreshGeometry()
        for id in tracked.keys {
            place(id)
        }
        scheduleRedraw()
    }

    private func placeZones(_ zones: [Zone], in area: CGRect, on uuid: String) -> [PlacedZone] {
        zones.map { zone in
            let side = store.side(of: zone, on: uuid)
            return PlacedZone(zone, in: area, side: side, size: ZoneBar.size(of: side, compact: store.compactTabs))
        }
    }

    private func refreshGeometry() {
        if zoneInfo != nil { hideBadge() }
        let displays = Displays.active()
        let showing = Displays.showingFullScreen()
        var next: [String: Surface] = [:]
        for uuid in store.displays.keys {
            guard let id = displays.first(where: { Displays.uuid($0) == uuid }),
                  let screen = NSScreen.screens.first(where: { $0.displayID == id }) else { continue }
            var area = flip(screen.visibleFrame)
            let bounds = flip(screen.frame)
            if let menuBar = menuBarBottom(in: bounds), menuBar < area.minY, area.minY - menuBar <= 4 {
                area = CGRect(x: area.minX, y: menuBar, width: area.width, height: area.maxY - menuBar)
            }
            if showing.contains(uuid), let previous = surfaces[uuid], previous.bounds == bounds {
                area = previous.area
            }
            next[uuid] = Surface(
                uuid: uuid, screen: screen, area: area, bounds: bounds,
                others: displays.filter { $0 != id }.map { CGDisplayBounds($0) },
                placed: placeZones(store.zones(of: uuid), in: area, on: uuid)
            )
        }
        surfaces = next
    }

    private func menuBarBottom(in display: CGRect) -> CGFloat? {
        guard let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as NSArray? else { return nil }
        let level = Int(CGWindowLevelForKey(.mainMenuWindow))
        for case let info as NSDictionary in list {
            guard (info["kCGWindowLayer"] as? NSNumber)?.intValue == level,
                  let rectInfo = info["kCGWindowBounds"] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: rectInfo as CFDictionary),
                  rect.minY == display.minY, rect.minX == display.minX, rect.width == display.width else { continue }
            return rect.maxY
        }
        return nil
    }

    private func flip(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: top - rect.maxY, width: rect.width, height: rect.height)
    }

    private var inGesture: Bool {
        let now = ProcessInfo.processInfo.systemUptime
        return (mouseIsDown && now - downAt < 30) || now - upAt < 0.4
    }

    func mouseDown(at point: CGPoint, clicks: Int64) -> Bool {
        guard running, !paused else { return false }
        if let key = zoneInfo, !isOnLabel(point, of: key) { hideBadge() }
        if settleTimer != nil { settle() }
        doubleClick = clicks >= 2
        mouseIsDown = true
        downAt = ProcessInfo.processInfo.systemUptime
        downPoint = point
        upPoint = nil
        pressedFrames = tracked.compactMapValues(\.known)
        resizedWhileDown.removeAll()
        gesture.removeAll()
        gestureOnSurface = surface(at: point) != nil
        if let window = zoomButtonWindow(at: point) {
            zooming = window
            swallowUp = true
            return true
        }
        return false
    }

    func mouseUp(at point: CGPoint) -> Bool {
        guard running, !paused else { return false }
        mouseIsDown = false
        upAt = ProcessInfo.processInfo.systemUptime
        upPoint = point
        if zoneInfo == nil { badge.hide() }
        if swallowUp {
            swallowUp = false
            if let window = zooming {
                zooming = nil
                after(0) { [weak self] in self?.toggleFill(window) }
            }
            return true
        }
        gestureOnSurface = gestureOnSurface || surface(at: point) != nil
        if gestureOnSurface || !gesture.isEmpty { scheduleSettle() }
        return false
    }

    func tapDisabled() {
        if running, !paused { _ = tap.start() }
    }

    private func remember(_ element: AXUIElement) {
        if !gesture.contains(where: { CFEqual($0, element) }) { gesture.append(element) }
        if !mouseIsDown { scheduleSettle() }
    }

    private func scheduleSettle() {
        settleTimer?.invalidate()
        settleTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.settle() }
        }
    }

    private func settle() {
        settleTimer?.invalidate()
        settleTimer = nil
        var elements = gesture
        gesture.removeAll()
        guard running, !paused, let down = downPoint, let up = upPoint else { return }
        if gestureOnSurface, let (focused, _) = focusedWindow(), !elements.contains(where: { CFEqual($0, focused) }) {
            elements.append(focused)
        }
        gestureOnSurface = false
        let zoom = doubleClick ? down : nil
        doubleClick = false
        for element in elements {
            settle(element, down: down, up: up, doubleClick: zoom)
        }
    }

    private func settle(_ element: AXUIElement, down: CGPoint, up: CGPoint, doubleClick: CGPoint?) {
        guard let frame = synced(element) else { return }
        guard let id = trackedID(element) ?? element.windowID, let window = tracked[id] else {
            if let surface = surface(at: frame.center), let pid = element.pid, pid != ownPID, element.isStandardWindow {
                let point = surface.bounds.contains(up) ? up : frame.center
                adopt(element, pid: pid, display: surface.uuid, zone: surface.placed.zone(at: point)?.id ?? Self.defaultZone, fit: .keep)
            }
            return
        }
        guard let old = window.known else {
            place(id)
            return
        }
        let dragged = pressedFrames[id].map { Geometry.drags($0, from: down, to: up) } == true && !resizedWhileDown.contains(id)
        switch Geometry.gesture(from: old, to: frame, doubleClick: doubleClick, dragged: dragged) {
        case .unchanged:
            return
        case .zoomed:
            toggleFill(element, from: old)
        case .resized:
            if !resizeZones(id, down: down, old: old, now: frame) {
                place(id, .free)
            }
        case .tiled:
            land(element, window, id, at: up, home: .fill, away: .fill)
        case .moved:
            if old.contains(down) {
                land(element, window, id, at: up, home: .free, away: .keep)
            } else {
                place(id)
            }
        }
    }

    private func land(_ element: AXUIElement, _ window: Tracked, _ id: CGWindowID, at up: CGPoint, home: Fit, away: Fit) {
        if surfaces[window.display]?.bounds.contains(up) == true {
            place(id, home)
        } else if let other = surface(at: up) {
            adopt(element, pid: window.pid, display: other.uuid, zone: other.placed.zone(at: up)?.id ?? Self.defaultZone, fit: away)
        } else {
            release(id)
        }
    }

    private func synced(_ element: AXUIElement) -> CGRect? {
        guard let frame = element.frame else { return nil }
        guard let id = element.windowID, let server = serverFrame(of: id), !Geometry.same(frame, server) else { return frame }
        element.setFrame(server)
        return server
    }

    private func serverFrame(of id: CGWindowID) -> CGRect? {
        guard let list = CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as NSArray?,
              let info = list.firstObject as? NSDictionary,
              let rectInfo = info["kCGWindowBounds"] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: rectInfo as CFDictionary)
    }

    private func resizeZones(_ id: CGWindowID, down: CGPoint, old: CGRect, now: CGRect) -> Bool {
        guard let (surface, zones) = movedDividers(id, down: down, old: old, now: now) else { return false }
        store.setDraft(zones, on: surface.uuid)
        reflow()
        return true
    }

    private func movedDividers(_ id: CGWindowID, down: CGPoint, old: CGRect, now: CGRect) -> (Surface, [Zone])? {
        guard !store.lockZones, let (surface, zone) = placement(of: id), Geometry.same(old, zone.content) else { return nil }
        var zones = store.zones(of: surface.uuid)
        var changed = false
        for move in Geometry.edgeMoves(old: old, now: now, grabbed: down, area: surface.area, inset: zone.margins) {
            if let next = Geometry.moving(zones, move) {
                zones = next
                changed = true
            }
        }
        return changed ? (surface, zones) : nil
    }

    private func showSize(_ id: CGWindowID, _ frame: CGRect?) {
        zoneInfo = nil
        guard let frame, let old = tracked[id]?.known, let down = downPoint,
              Geometry.gesture(from: old, to: frame) == .resized, let (surface, _) = placement(of: id) else {
            badge.hide()
            return
        }
        var lines: [(label: String, value: String)] = []
        if let (_, zones) = movedDividers(id, down: down, old: old, now: frame) {
            for zone in placeZones(zones, in: surface.area, on: surface.uuid) {
                guard surface.placed.first(where: { $0.id == zone.id })?.full.size != zone.full.size else { continue }
                lines.append(("Zona \(zone.id)", Self.size(zone.full.size)))
            }
        }
        let scale = panelScale(surface)
        lines.append(("Ventana", Self.size(frame.size)))
        lines.append(("Físicos", Self.size(CGSize(width: frame.width * scale, height: frame.height * scale))))
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }?.frame ?? surface.screen.frame
        badge.show(lines) { size in
            let gap: CGFloat = 16
            let x = mouse.x + gap + size.width <= screen.maxX ? mouse.x + gap : mouse.x - gap - size.width
            let y = mouse.y - gap - size.height >= screen.minY ? mouse.y - gap - size.height : mouse.y + gap
            return NSPoint(x: x.rounded(), y: y.rounded())
        }
    }

    private func toggleZoneInfo(_ uuid: String, _ id: String) {
        let key = uuid + "|" + id
        guard zoneInfo != key, let surface = surfaces[uuid], let zone = surface.placed.first(where: { $0.id == id }),
              let fraction = store.zones(of: uuid).first(where: { $0.id == id }) else {
            hideBadge()
            return
        }
        zoneInfo = key
        let scale = panelScale(surface)
        let lines: [(label: String, value: String)] = [
            ("Zona \(id)", Self.size(zone.full.size)),
            ("Físicos", Self.size(CGSize(width: zone.full.width * scale, height: zone.full.height * scale))),
            ("Porcentaje", "\(Self.percent(fraction.w)) % × \(Self.percent(fraction.h)) %"),
        ]
        let bounds = surface.bounds
        badge.show(lines) { size in
            let x = zone.side == .right ? zone.bar.minX - 4 - size.width : zone.content.minX + 4
            let y = zone.side == .bottom ? zone.bar.minY - 4 - size.height : zone.content.minY + 4
            let origin = CGPoint(x: min(max(x, bounds.minX), bounds.maxX - size.width), y: min(max(y, bounds.minY), bounds.maxY - size.height))
            return flip(CGRect(origin: origin, size: size)).origin
        }
    }

    private func isOnLabel(_ point: CGPoint, of key: String) -> Bool {
        surfaces.values.contains { surface in
            surface.placed.contains { zone in
                surface.uuid + "|" + zone.id == key && ZoneBar.label(of: zone.widened(to: ZoneBar.sideWidth), side: zone.side).contains(point)
            }
        }
    }

    private func hideBadge() {
        zoneInfo = nil
        badge.hide()
    }

    private static func size(_ size: CGSize) -> String {
        "\(Int(size.width.rounded())) × \(Int(size.height.rounded())) px"
    }

    private static func percent(_ value: Double) -> Int {
        Int((value * 100).rounded())
    }

    private func panelScale(_ surface: Surface) -> CGFloat {
        let native = surface.screen.displayID.flatMap(Displays.nativeSize).map(\.width)
        return native.map { $0 / surface.screen.frame.width } ?? surface.screen.backingScaleFactor
    }

    private func element(at point: CGPoint) -> AXUIElement? {
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element) == .success else { return nil }
        return element
    }

    private func zoomButtonWindow(at point: CGPoint) -> AXUIElement? {
        guard surface(at: point) != nil else { return nil }
        let nearTitle = tracked.values.contains { window in
            guard let known = window.known else { return false }
            return point.x >= known.minX && point.x <= known.minX + 100 && point.y >= known.minY && point.y <= known.minY + 52
        }
        guard nearTitle, let hit = element(at: point), let subrole = hit.subrole,
              subrole == kAXFullScreenButtonSubrole || subrole == kAXZoomButtonSubrole else { return nil }
        return hit.element(kAXWindowAttribute)
    }

    private func follow(_ point: CGPoint) {
        carryPoint = point
        guard carryTimer == nil else { return }
        let timer = Timer(timeInterval: Self.carryInterval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.moveCarried() }
        }
        RunLoop.main.add(timer, forMode: .common)
        carryTimer = timer
    }

    private func moveCarried() {
        carryTimer = nil
        guard let carried = carry, let point = carryPoint, let grip = carried.grip else { return }
        carried.element.setOrigin(CGPoint(x: point.x - grip.x, y: point.y - grip.y))
    }

    private func stopCarry() {
        carry = nil
        carryPoint = nil
        carryTimer?.invalidate()
        carryTimer = nil
    }

    private func drop(_ carried: Carry, at point: CGPoint) {
        let window = carried.element
        guard let pid = window.pid else { return }
        if let grip = carried.grip { window.setOrigin(CGPoint(x: point.x - grip.x, y: point.y - grip.y)) }
        if let surface = surface(at: point), let zone = surface.placed.zone(at: point) {
            adopt(window, pid: pid, display: surface.uuid, zone: zone.id, fit: .keep)
            window.focus()
        } else if let id = trackedID(window) {
            release(id)
        }
    }

    private func showGhost(at point: CGPoint) {
        let target = surface(at: point).flatMap { surface in
            surface.placed.zone(at: point).map { (key: surface.uuid + "|" + $0.id, zone: $0) }
        }
        guard target?.key != ghostKey else { return }
        ghostKey = target?.key
        if let zone = target?.zone { ghost.show(flip(zone.full)) } else { ghost.hide() }
    }

    private func hideGhost() {
        ghostKey = nil
        ghost.hide()
    }

    private func dragTab(_ id: CGWindowID, _ point: NSPoint) {
        let location = global(point)
        showGhost(at: location)
        if carry == nil {
            guard let window = tracked[id], let frame = window.element.frame else { return }
            let element = window.element
            if window.minimized { element.setMinimized(false) }
            carry = Carry(element: element, start: frame.origin, grip: CGPoint(x: (frame.width / 2).rounded(), y: 12))
            element.raise()
        }
        follow(location)
    }

    private func dropTab(_ id: CGWindowID, at point: NSPoint) {
        hideGhost()
        if let carried = carry {
            stopCarry()
            drop(carried, at: global(point))
        } else if let window = tracked[id] {
            drop(Carry(element: window.element, start: nil, grip: nil), at: global(point))
        }
    }

    private func reorderTab(_ id: CGWindowID, to index: Int) {
        hideGhost()
        if let carried = carry {
            stopCarry()
            if let start = carried.start { carried.element.setOrigin(start) }
            scheduleRedraw()
        }
        guard let display = tracked[id]?.display, let (_, zone) = placement(of: id) else { return }
        var members = self.members(of: display, zone: zone.id, rank: onScreenRank())
        guard let current = members.firstIndex(of: id), current != index, members.indices.contains(index) else { return }
        members.remove(at: current)
        members.insert(id, at: index)
        for member in members {
            counter += 1
            tracked[member]?.order = counter
        }
        redraw()
    }

    private func scheduleRedraw() {
        guard redrawTimer == nil else { return }
        redrawTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.redraw() }
        }
    }

    private func redraw() {
        redrawTimer = nil
        guard running, !paused, !surfaces.isEmpty else {
            closeBars()
            return
        }
        if !tap.isEnabled { _ = tap.start() }
        let rank = onScreenRank()
        let covered = Displays.showingFullScreen()
        let shown = surfaces.values.filter { $0.screen.uuid.map { !covered.contains($0) } ?? true }
        var keys = Set<String>()
        for surface in shown {
            for zone in surface.placed {
                let key = surface.uuid + "|" + zone.id
                keys.insert(key)
                let members = members(of: surface.uuid, zone: zone.id, rank: rank)
                let active = members.filter { rank[$0] != nil }.min { rank[$0] ?? .max < rank[$1] ?? .max }
                let tabs = members.compactMap { id -> Tab? in
                    guard let window = tracked[id] else { return nil }
                    return Tab(
                        id: id,
                        title: window.title.isEmpty ? NSRunningApplication(processIdentifier: window.pid)?.localizedName ?? "" : window.title,
                        icon: icon(for: window.pid),
                        active: id == active,
                        minimized: window.minimized
                    )
                }
                let bar = bars[key] ?? ZoneBar(
                    onSelect: { [weak self] id in self?.select(id) },
                    onDrag: { [weak self] id, point in self?.dragTab(id, point) },
                    onDrop: { [weak self] id, point in self?.dropTab(id, at: point) },
                    onReorder: { [weak self] id, index in self?.reorderTab(id, to: index) },
                    onMenu: { [weak self] id in self?.tabMenu(id) },
                    onZoneMenu: { [weak self, uuid = surface.uuid, id = zone.id] in self?.onZoneMenu?(uuid, id) },
                    onButton: { [weak self] id, button in self?.press(button, on: id) },
                    onLabel: { [weak self, uuid = surface.uuid, id = zone.id] in self?.toggleZoneInfo(uuid, id) }
                )
                bars[key] = bar
                bar.show(
                    label: zone.id, tabs: tabs, compact: store.compactTabs, side: zone.side,
                    frame: flip(zone.bar), wide: flip(zone.widened(to: ZoneBar.sideWidth)),
                    expandable: store.compactTabs && zone.side.vertical,
                    leftLine: store.showBorders && zone.bar.minX == zone.full.minX && zone.full.minX > surface.area.minX + Geometry.pixelTolerance,
                    topLine: store.showBorders && zone.bar.minY == zone.full.minY && zone.full.minY > surface.area.minY + Geometry.pixelTolerance
                )
            }
        }
        for (key, bar) in bars where !keys.contains(key) {
            bar.close()
            bars[key] = nil
        }
        if store.showBorders {
            borders.show(shown.sorted { $0.uuid < $1.uuid }.flatMap { surface in
                Geometry.uncovered(
                    Geometry.dividers(surface.placed, in: surface.area, thickness: Self.lineWidth), by: surface.placed.map(\.bar)
                ).map(flip)
            })
        } else {
            borders.hide()
        }
    }

    func setBordersVisible(_ visible: Bool) {
        store.showBorders = visible
        scheduleRedraw()
    }

    func setCompactTabs(_ compact: Bool) {
        store.compactTabs = compact
        reflow()
    }

    func setSnap(_ snap: Bool) {
        store.snap = snap
        for id in tracked.keys {
            place(id, .free)
        }
        scheduleRedraw()
    }

    private func members(of display: String, zone: String, rank: [CGWindowID: Int]) -> [CGWindowID] {
        tracked
            .filter { (rank[$0.key] != nil || $0.value.minimized) && $0.value.display == display && placement(of: $0.key)?.1.id == zone }
            .sorted { $0.value.order < $1.value.order }
            .map(\.key)
    }

    private func onScreenRank() -> [CGWindowID: Int] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as NSArray? else { return [:] }
        var rank: [CGWindowID: Int] = [:]
        for case let info as NSDictionary in list {
            if let number = info["kCGWindowNumber"] as? NSNumber { rank[number.uint32Value] = rank.count }
        }
        return rank
    }

    private func icon(for pid: pid_t) -> NSImage? {
        if let icon = icons[pid] { return icon }
        let icon = NSRunningApplication(processIdentifier: pid)?.icon
        icons[pid] = icon
        return icon
    }

    private func select(_ id: CGWindowID) {
        guard let window = tracked[id] else { return }
        if window.minimized { window.element.setMinimized(false) }
        window.element.focus()
        scheduleRedraw()
    }

    private func closeBars() {
        for bar in bars.values {
            bar.close()
        }
        bars.removeAll()
        borders.hide()
    }

    private func after(_ seconds: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        let timer = Timer(timeInterval: seconds, repeats: false) { _ in
            MainActor.assumeIsolated { action() }
        }
        RunLoop.main.add(timer, forMode: .common)
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    var uuid: String? {
        displayID.flatMap(Displays.uuid)
    }
}
