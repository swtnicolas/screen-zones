import Foundation

struct DisplayConfig: Codable, Equatable {
    var layout = Layout.single.name
    var draft: [Zone]?
    var tabsAt: Side?

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        layout = (try? container.decodeIfPresent(String.self, forKey: .layout)) ?? Layout.single.name
        draft = (try? container.decodeIfPresent([Zone].self, forKey: .draft)) ?? nil
        tabsAt = (try? container.decodeIfPresent(Side.self, forKey: .tabsAt)) ?? nil
    }
}

extension Layout {
    static func unique(_ name: String, among names: [String]) -> String {
        let taken = Set((names + [single.name]).map { $0.lowercased() })
        guard taken.contains(name.lowercased()) else { return name }
        return (2...).lazy.map { "\(name) \($0)" }.first { !taken.contains($0.lowercased()) } ?? name
    }
}

struct Rule: Codable, Equatable {
    var display: String?
    var zone: String
}

struct SavedWindow: Codable, Equatable {
    var pid: Int32
    var display: String
    var zone: String
    var width: Double
    var height: Double
    var filled: Bool
}

@MainActor
final class Store {
    private let defaults: UserDefaults
    private(set) var displays: [String: DisplayConfig]

    var free: Set<String> {
        didSet { defaults.set(free.sorted(), forKey: "free") }
    }

    private(set) var layouts: [Layout] {
        didSet { defaults.set(try? JSONEncoder().encode(layouts), forKey: "layouts") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        displays = defaults.data(forKey: "displays").flatMap { try? JSONDecoder().decode([String: DisplayConfig].self, from: $0) } ?? [:]
        free = Set(defaults.stringArray(forKey: "free") ?? [])
        layouts = defaults.data(forKey: "layouts").flatMap { try? JSONDecoder().decode([Layout].self, from: $0) } ?? []
    }

    var choices: [Layout] {
        [Layout.single] + layouts
    }

    func layout(named name: String) -> Layout {
        layouts.first { $0.name == name } ?? .single
    }

    func layout(of uuid: String) -> Layout? {
        displays[uuid].map { layout(named: $0.layout) }
    }

    func zones(of uuid: String) -> [Zone] {
        guard let config = displays[uuid] else { return Layout.single.zones }
        return config.draft ?? layout(named: config.layout).zones
    }

    func hasDraft(_ uuid: String) -> Bool {
        displays[uuid]?.draft != nil
    }

    func setDraft(_ zones: [Zone], on uuid: String) {
        update(uuid) { $0.draft = zones == layout(named: $0.layout).zones ? nil : zones }
    }

    func discardDraft(on uuid: String) {
        update(uuid) { $0.draft = nil }
    }

    func choose(_ name: String, on uuid: String) {
        update(uuid) {
            $0.layout = name
            $0.draft = nil
        }
    }

    func setZones(_ zones: [Zone], of name: String) {
        guard let index = layouts.firstIndex(where: { $0.name == name }) else { return }
        layouts[index].zones = zones
        for (uuid, config) in displays where config.layout == name {
            displays[uuid]?.draft = nil
        }
        save()
    }

    func add(_ layout: Layout) -> String {
        let name = Layout.unique(layout.name, among: layouts.map(\.name))
        layouts.append(Layout(name: name, zones: layout.zones))
        return name
    }

    func rename(_ name: String, to proposed: String) {
        guard proposed != name, let index = layouts.firstIndex(where: { $0.name == name }) else { return }
        let renamed = Layout.unique(proposed, among: layouts.filter { $0.name != name }.map(\.name))
        layouts[index].name = renamed
        for (uuid, config) in displays where config.layout == name {
            displays[uuid]?.layout = renamed
        }
        save()
    }

    func remove(_ name: String) {
        layouts.removeAll { $0.name == name }
        for (uuid, config) in displays where config.layout == name {
            displays[uuid]?.layout = Layout.single.name
            displays[uuid]?.draft = nil
        }
        save()
    }

    var nextName: String {
        Layout.unique("Disposición \(layouts.count + 1)", among: layouts.map(\.name))
    }

    func side(of uuid: String) -> Side {
        displays[uuid]?.tabsAt ?? tabsAt
    }

    func side(of zone: Zone, on uuid: String) -> Side {
        zone.tabsAt ?? side(of: uuid)
    }

    func setSide(_ side: Side?, on uuid: String) {
        update(uuid) { $0.tabsAt = side }
    }

    func setSide(_ side: Side?, ofZone id: String, on uuid: String) {
        guard let config = displays[uuid] else { return }
        guard let index = layouts.firstIndex(where: { $0.name == config.layout }) else {
            setSide(side, on: uuid)
            return
        }
        func sided(_ zones: [Zone]) -> [Zone] {
            zones.map { zone in
                var zone = zone
                if zone.id == id { zone.tabsAt = side }
                return zone
            }
        }
        layouts[index].zones = sided(layouts[index].zones)
        for (key, other) in displays where other.layout == config.layout {
            displays[key]?.draft = other.draft.map(sided)
        }
        save()
    }

    func update(_ uuid: String, _ change: (inout DisplayConfig) -> Void) {
        guard var config = displays[uuid] else { return }
        change(&config)
        displays[uuid] = config
        save()
    }

    func enable(_ uuid: String) {
        guard displays[uuid] == nil else { return }
        displays[uuid] = DisplayConfig()
        save()
    }

    func disable(_ uuid: String) {
        displays[uuid] = nil
        save()
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(displays), forKey: "displays")
    }

    var showBorders: Bool {
        get { defaults.object(forKey: "borders") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "borders") }
    }

    var compactTabs: Bool {
        get { defaults.bool(forKey: "compactTabs") }
        set { defaults.set(newValue, forKey: "compactTabs") }
    }

    var snap: Bool {
        get { defaults.bool(forKey: "snap") }
        set { defaults.set(newValue, forKey: "snap") }
    }

    var lockZones: Bool {
        get { defaults.object(forKey: "lockZones") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "lockZones") }
    }

    var tabsAt: Side {
        get { defaults.string(forKey: "tabsAt").flatMap(Side.init(rawValue:)) ?? .top }
        set { defaults.set(newValue.rawValue, forKey: "tabsAt") }
    }

    var rules: [String: Rule] {
        get { defaults.data(forKey: "rules").flatMap { try? JSONDecoder().decode([String: Rule].self, from: $0) } ?? [:] }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "rules") }
    }

    var lastZones: [String: [String: Rule]] {
        get { defaults.data(forKey: "last").flatMap { try? JSONDecoder().decode([String: [String: Rule]].self, from: $0) } ?? [:] }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "last") }
    }

    var windows: [String: SavedWindow] {
        get { defaults.data(forKey: "windows").flatMap { try? JSONDecoder().decode([String: SavedWindow].self, from: $0) } ?? [:] }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "windows") }
    }
}
