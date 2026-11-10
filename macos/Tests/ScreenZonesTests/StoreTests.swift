import Foundation
import Testing
@testable import ScreenZones

private final class MemoryDefaults: UserDefaults, @unchecked Sendable {
    private var values: [String: Any]

    init(values: [String: Any]) {
        self.values = values
        super.init(suiteName: nil)!
    }

    override func object(forKey key: String) -> Any? { values[key] }
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
    override func set(_ value: Bool, forKey key: String) { values[key] = value }
    override func removeObject(forKey key: String) { values[key] = nil }
    override func data(forKey key: String) -> Data? { values[key] as? Data }
    override func string(forKey key: String) -> String? { values[key] as? String }
    override func stringArray(forKey key: String) -> [String]? { values[key] as? [String] }
    override func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
}

@MainActor
struct StoreTests {
    private static let halves = [Zone(id: "A", x: 0, y: 0, w: 0.5, h: 1), Zone(id: "B", x: 0.5, y: 0, w: 0.5, h: 1)]
    private static let moved = [Zone(id: "A", x: 0, y: 0, w: 0.6, h: 1), Zone(id: "B", x: 0.6, y: 0, w: 0.4, h: 1)]
    private static let thirds = [Zone(id: "A", x: 0, y: 0, w: 1.0 / 3, h: 1), Zone(id: "B", x: 1.0 / 3, y: 0, w: 2.0 / 3, h: 1)]

    private func withStore(_ body: (Store, UserDefaults, String) -> Void) {
        let defaults = MemoryDefaults(values: [:])
        let store = Store(defaults: defaults)
        let name = store.add(Layout(name: "Dos", zones: Self.halves))
        for uuid in ["one", "two"] {
            store.enable(uuid)
            store.choose(name, on: uuid)
        }
        body(store, defaults, name)
    }

    @Test func aMovedDividerChangesOnlyItsDisplayAndLeavesTheLayoutAsSaved() {
        withStore { store, _, name in
            store.setDraft(Self.moved, on: "one")
            #expect(store.zones(of: "one") == Self.moved)
            #expect(store.zones(of: "two") == Self.halves)
            #expect(store.layout(named: name).zones == Self.halves)
        }
    }

    @Test func unsavedZonesSurviveARelaunch() {
        withStore { store, defaults, _ in
            store.setDraft(Self.moved, on: "one")
            #expect(Store(defaults: defaults).zones(of: "one") == Self.moved)
        }
    }

    @Test func dividersMovedBackToTheSavedZonesLeaveNothingUnsaved() {
        withStore { store, _, _ in
            store.setDraft(Self.moved, on: "one")
            store.setDraft(Self.halves, on: "one")
            #expect(!store.hasDraft("one"))
        }
    }

    @Test func savingALayoutClearsTheUnsavedZonesOfEveryDisplayShowingIt() {
        withStore { store, _, name in
            store.setDraft(Self.moved, on: "one")
            store.setDraft(Self.moved, on: "two")
            store.setZones(Self.thirds, of: name)
            #expect(store.zones(of: "one") == Self.thirds)
            #expect(store.zones(of: "two") == Self.thirds)
        }
    }

    @Test func choosingALayoutDiscardsTheDisplaysUnsavedZones() {
        withStore { store, _, name in
            store.setDraft(Self.moved, on: "one")
            store.choose(name, on: "one")
            #expect(store.zones(of: "one") == Self.halves)
        }
    }

    @Test func aZonesBarSideFallsBackToItsDisplaysAndTheDisplaysToTheGeneralOne() {
        withStore { store, _, _ in
            store.tabsAt = .right
            store.setSide(.bottom, on: "one")
            #expect(store.side(of: Zone(id: "A", x: 0, y: 0, w: 1, h: 1, tabsAt: .left), on: "one") == .left)
            #expect(store.side(of: Zone(id: "A", x: 0, y: 0, w: 1, h: 1), on: "one") == .bottom)
            #expect(store.side(of: Zone(id: "A", x: 0, y: 0, w: 1, h: 1), on: "two") == .right)
        }
    }

    @Test func aZonesBarSideGoesIntoItsLayoutAndEveryUnsavedCopyOfIt() {
        withStore { store, _, name in
            store.setDraft(Self.moved, on: "one")
            store.setSide(.left, ofZone: "B", on: "two")
            #expect(store.layout(named: name).zones.map(\.tabsAt) == [nil, .left])
            #expect(store.zones(of: "one").map(\.tabsAt) == [nil, .left])
            #expect(store.zones(of: "one").map(\.w) == Self.moved.map(\.w))
            #expect(store.side(of: "two") == .top)
        }
    }

    @Test func onOneColumnAZonesBarSideIsItsDisplays() {
        withStore { store, _, _ in
            store.enable("three")
            store.setSide(.bottom, ofZone: "A", on: "three")
            #expect(store.side(of: "three") == .bottom)
            #expect(store.zones(of: "three") == Layout.single.zones)
        }
    }

    @Test func removingALayoutSendsItsDisplaysToOneColumnWithoutTheirUnsavedZones() {
        withStore { store, _, name in
            store.setDraft(Self.moved, on: "one")
            store.remove(name)
            #expect(store.zones(of: "one") == Layout.single.zones)
        }
    }
}
