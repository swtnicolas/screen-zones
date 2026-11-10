import Foundation
import Testing
@testable import ScreenZones

@Test func aDisplaySavedWithoutALayoutShowsOneColumnWithTheGeneralBarSide() throws {
    let json = #"{}"#
    let config = try JSONDecoder().decode(DisplayConfig.self, from: Data(json.utf8))
    #expect(config.layout == Layout.single.name)
    #expect(config.tabsAt == nil)
}

@Test func aBarSideTheAppDoesNotKnowIsDroppedWithoutLosingTheDisplayOrTheLayout() throws {
    let display = #"{"layout":"Trabajo","tabsAt":"middle"}"#
    let config = try JSONDecoder().decode(DisplayConfig.self, from: Data(display.utf8))
    #expect(config.layout == "Trabajo")
    #expect(config.tabsAt == nil)
    let layout = #"{"name":"Trabajo","zones":[{"id":"A","x":0,"y":0,"w":1,"h":1,"tabsAt":"middle"}]}"#
    #expect(try JSONDecoder().decode(Layout.self, from: Data(layout.utf8)).zones == Layout.single.zones)
}

@Test func aTakenNameGetsTheFirstFreeNumberIgnoringCase() {
    #expect(Layout.unique("Trabajo", among: ["trabajo", "Trabajo 2"]) == "Trabajo 3")
    #expect(Layout.unique("una columna", among: []) == "una columna 2")
    #expect(Layout.unique("Casa", among: ["Trabajo"]) == "Casa")
}
