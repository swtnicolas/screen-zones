import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = Store()
    private lazy var manager = ZoneManager(store: store)
    private var statusItem: NSStatusItem?
    private var trustTimer: Timer?
    private var quitObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        item.button?.toolTip = "ScreenZones"
        statusItem = item
        quitObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("local.screenzones.quit"), object: nil, queue: nil
        ) { _ in
            RunLoop.main.perform { MainActor.assumeIsolated { NSApp.terminate(nil) } }
        }
        manager.onStateChange = { [weak self] in self?.updateIcon() }
        manager.onTabMenu = { [weak self] id, bundle, name in self?.tabMenu(id, bundle: bundle, name: name) }
        manager.onZoneMenu = { [weak self] display, zone in self?.zoneMenu(display, zone) }
        updateIcon()
        if AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) {
            manager.start()
        } else {
            trustTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkTrust() }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        manager.saveWindows()
    }

    private func checkTrust() {
        guard AXIsProcessTrusted() else { return }
        trustTimer?.invalidate()
        trustTimer = nil
        manager.start()
    }

    private func updateIcon() {
        statusItem?.button?.image = manager.running && !manager.paused ? StatusIcon.active : StatusIcon.idle
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        fill(menu, zone: nil)
    }

    private func zoneMenu(_ display: String, _ zone: String) -> NSMenu {
        let menu = NSMenu()
        fill(menu, zone: (display: display, id: zone))
        return menu
    }

    private func fill(_ menu: NSMenu, zone: (display: String, id: String)?) {
        guard manager.running else {
            menu.addItem(ActionItem("Esperando el permiso de Accesibilidad"))
            return
        }
        let displays = manager.menuDisplays
        if let zone, let display = displays.first(where: { $0.uuid == zone.display && $0.enabled }),
           let sides = zoneSideItem("Barra de esta zona", display: zone.display, zone: zone.id) {
            menu.addItem(ActionItem("Zona \(zone.id) · \(display.name)"))
            menu.addItem(sides)
            menu.addItem(.separator())
        }
        for display in displays {
            menu.addItem(displayItem(display))
        }
        menu.addItem(.separator())
        let tabs = NSMenu()
        addSides(to: tabs, checked: store.tabsAt) { [weak self] side in self?.manager.setTabsAt(side) }
        tabs.addItem(.separator())
        tabs.addItem(ActionItem("Compacta", checked: store.compactTabs) { [weak self] in
            guard let self else { return }
            self.manager.setCompactTabs(!self.store.compactTabs)
        })
        menu.addItem(item("Barra de pestañas", tabs))
        menu.addItem(ActionItem("Mostrar bordes de las zonas", checked: store.showBorders) { [weak self] in
            guard let self else { return }
            self.manager.setBordersVisible(!self.store.showBorders)
        })
        menu.addItem(.separator())
        menu.addItem(ActionItem("Bloquear el tamaño de las zonas", checked: store.lockZones) { [weak self] in
            self?.store.lockZones.toggle()
        })
        menu.addItem(ActionItem("Imantar las ventanas a su zona", checked: store.snap) { [weak self] in
            guard let self else { return }
            self.manager.setSnap(!self.store.snap)
        })
        menu.addItem(freeItem())
        menu.addItem(.separator())
        menu.addItem(ActionItem(manager.paused ? "Reanudar" : "Pausar") { [weak self] in
            guard let self else { return }
            self.manager.setPaused(!self.manager.paused)
        })
    }

    private func displayItem(_ display: ManagedDisplay) -> NSMenuItem {
        let submenu = NSMenu()
        submenu.addItem(ActionItem("Usar zonas en esta pantalla", checked: display.enabled) { [weak self] in
            self?.manager.setEnabled(!display.enabled, display: display)
        })
        guard let config = store.displays[display.uuid] else { return item("\(display.name) — sin zonas", submenu) }
        let uuid = display.uuid
        let current = store.layout(named: config.layout).name
        let unsaved = store.hasDraft(uuid)
        submenu.addItem(.separator())
        for layout in store.choices {
            let title = unsaved && layout.name == current ? "\(layout.name) (sin guardar)" : layout.name
            submenu.addItem(ActionItem(title, checked: layout.name == current) { [weak self] in
                self?.manager.setLayout(layout.name, on: uuid)
            })
        }
        submenu.addItem(.separator())
        let sides = NSMenu()
        sides.addItem(ActionItem("Como las demás (\(store.tabsAt.name.lowercased()))", checked: config.tabsAt == nil) { [weak self] in
            self?.manager.setSide(nil, on: uuid)
        })
        sides.addItem(.separator())
        addSides(to: sides, checked: config.tabsAt) { [weak self] side in self?.manager.setSide(side, on: uuid) }
        submenu.addItem(item("Barra de pestañas", sides))
        submenu.addItem(.separator())
        if current != Layout.single.name {
            let manage = NSMenu()
            manage.addItem(ActionItem("Editar…") { [weak self] in self?.manager.editZones(on: uuid) })
            if unsaved {
                manage.addItem(ActionItem("Descartar los cambios sin guardar") { [weak self] in self?.manager.discardChanges(on: uuid) })
            }
            manage.addItem(ActionItem("Renombrar…") { [weak self] in self?.renameLayout(current) })
            manage.addItem(ActionItem("Eliminar…") { [weak self] in self?.removeLayout(current) })
            submenu.addItem(item("«\(current)»", manage))
        }
        submenu.addItem(ActionItem("Nueva disposición…") { [weak self] in self?.newLayout(on: uuid) })
        return item("\(display.name) — \(current)\(unsaved ? " (sin guardar)" : "")", submenu)
    }

    private func zoneSideItem(_ title: String, display uuid: String, zone id: String) -> NSMenuItem? {
        guard let config = store.displays[uuid], let zone = store.zones(of: uuid).first(where: { $0.id == id }) else { return nil }
        let single = store.layout(named: config.layout).name == Layout.single.name
        let own = single ? config.tabsAt : zone.tabsAt
        let inherited = single ? store.tabsAt : store.side(of: uuid)
        let sides = NSMenu()
        sides.addItem(ActionItem("Como la pantalla (\(inherited.name.lowercased()))", checked: own == nil) { [weak self] in
            self?.manager.setSide(nil, ofZone: id, on: uuid)
        })
        sides.addItem(.separator())
        addSides(to: sides, checked: own) { [weak self] side in self?.manager.setSide(side, ofZone: id, on: uuid) }
        return item(title, sides)
    }

    private func addSides(to menu: NSMenu, checked: Side?, choose: @escaping (Side) -> Void) {
        for side in Side.allCases {
            menu.addItem(ActionItem(side.name, checked: side == checked) { choose(side) })
        }
    }

    private func item(_ title: String, _ submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    private func newLayout(on uuid: String) {
        guard let name = askName("Nueva disposición", button: "Crear", initial: store.nextName) else { return }
        manager.createLayout(named: name, on: uuid)
    }

    private func renameLayout(_ name: String) {
        guard let proposed = askName("Renombrar «\(name)»", button: "Renombrar", initial: name) else { return }
        store.rename(name, to: proposed)
    }

    private func removeLayout(_ name: String) {
        let alert = NSAlert()
        alert.messageText = "¿Eliminar «\(name)»?"
        alert.informativeText = "Las pantallas que la usan pasan a \(Layout.single.name)."
        alert.addButton(withTitle: "Eliminar").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancelar").keyEquivalent = "\u{1b}"
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        manager.removeLayout(name)
    }

    private func askName(_ title: String, button: String, initial: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancelar").keyEquivalent = "\u{1b}"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = initial
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? initial : name
    }

    private func tabMenu(_ id: CGWindowID, bundle: String?, name: String) -> NSMenu {
        let menu = NSMenu()
        let fill = manager.isFilled(id) ? "Volver al tamaño anterior" : "Maximizar en la zona"
        menu.addItem(ActionItem(fill) { [weak self] in self?.manager.toggleFill(id) })
        menu.addItem(ActionItem("Centrar en la zona") { [weak self] in self?.manager.center(id) })
        menu.addItem(ActionItem("Minimizar") { [weak self] in self?.manager.minimize(id) })
        menu.addItem(ActionItem("Cerrar") { [weak self] in self?.manager.close(id) })
        if let place = manager.zone(of: id), let sides = zoneSideItem("Barra de la zona \(place.zone)", display: place.display, zone: place.zone) {
            menu.addItem(.separator())
            menu.addItem(sides)
        }
        guard let bundle else { return menu }
        menu.addItem(.separator())
        let displays = manager.managedDisplays
        let rule = manager.rule(for: bundle)
        let opens = NSMenu()
        opens.addItem(ActionItem("La última zona que usó", checked: rule == nil) { [weak self] in
            self?.manager.setRule(nil, bundle: bundle)
        })
        opens.addItem(.separator())
        let leftmost = displays.first?.uuid
        for display in displays {
            let target = displays.count == 1 ? opens : NSMenu()
            for zone in manager.zoneIDs(of: display.uuid) {
                let checked = rule?.zone == zone && (rule?.display ?? leftmost) == display.uuid
                target.addItem(ActionItem("Zona \(zone)", checked: checked) { [weak self] in
                    self?.manager.setRule(Rule(display: display.uuid, zone: zone), bundle: bundle)
                })
            }
            if displays.count > 1 {
                opens.addItem(item(display.name, target))
            }
        }
        menu.addItem(item("Abrir \(name) en", opens))
        menu.addItem(ActionItem("\(name) ignora las zonas") { [weak self] in
            self?.manager.setFree(bundle: bundle)
        })
        return menu
    }

    private func freeItem() -> NSMenuItem {
        let submenu = NSMenu()
        let free = store.free.sorted()
        if free.isEmpty {
            submenu.addItem(ActionItem("Ninguna"))
        }
        for bundle in free {
            submenu.addItem(ActionItem(appName(bundle), checked: true) { [weak self] in
                self?.manager.setRule(nil, bundle: bundle)
            })
        }
        return item("Apps libres", submenu)
    }

    private func appName(_ bundle: String) -> String {
        if let name = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first?.localizedName { return name }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return bundle }
        return FileManager.default.displayName(atPath: url.path)
    }
}

final class ActionItem: NSMenuItem {
    private let handler: (() -> Void)?

    init(_ title: String, checked: Bool = false, handler: (() -> Void)? = nil) {
        self.handler = handler
        super.init(title: title, action: handler == nil ? nil : #selector(run), keyEquivalent: "")
        target = self
        state = checked ? .on : .off
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func run() {
        handler?()
    }
}
