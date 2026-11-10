import CoreGraphics
import Testing
@testable import ScreenZones

private let three = [
    Zone(id: "A", x: 0, y: 0, w: 0.5, h: 1),
    Zone(id: "B", x: 0.5, y: 0, w: 0.5, h: 0.5),
    Zone(id: "C", x: 0.5, y: 0.5, w: 0.5, h: 0.5),
]
private let two = [Zone(id: "A", x: 0, y: 0, w: 0.5, h: 1), Zone(id: "B", x: 0.5, y: 0, w: 0.5, h: 1)]
private let rows = [Zone(id: "A", x: 0, y: 0, w: 1, h: 0.5), Zone(id: "B", x: 0, y: 0.5, w: 1, h: 0.5)]
private let area = CGRect(x: 3272, y: -81, width: 1920, height: 1080)

private func matches(_ actual: [Zone]?, _ expected: [Zone]) -> Bool {
    guard let actual, actual.count == expected.count else { return false }
    return zip(actual, expected).allSatisfy { a, e in
        a.id == e.id
            && abs(a.x - e.x) < 1e-9 && abs(a.y - e.y) < 1e-9 && abs(a.w - e.w) < 1e-9 && abs(a.h - e.h) < 1e-9
    }
}

@Test func movingTheVerticalDividerResizesEveryZoneThatTouchesIt() {
    let moved = Geometry.moving(three, EdgeMove(axis: .x, from: 0.5, to: 0.6))
    #expect(matches(moved, [
        Zone(id: "A", x: 0, y: 0, w: 0.6, h: 1),
        Zone(id: "B", x: 0.6, y: 0, w: 0.4, h: 0.5),
        Zone(id: "C", x: 0.6, y: 0.5, w: 0.4, h: 0.5),
    ]))
}

@Test func movingTheHorizontalDividerLeavesTheFullHeightZoneAlone() {
    let moved = Geometry.moving(three, EdgeMove(axis: .y, from: 0.5, to: 0.3))
    #expect(matches(moved, [
        Zone(id: "A", x: 0, y: 0, w: 0.5, h: 1),
        Zone(id: "B", x: 0.5, y: 0, w: 0.5, h: 0.3),
        Zone(id: "C", x: 0.5, y: 0.3, w: 0.5, h: 0.7),
    ]))
}

@Test func screenEdgesNeverMove() {
    #expect(Geometry.moving(three, EdgeMove(axis: .x, from: 0, to: 0.1)) == nil)
    #expect(Geometry.moving(three, EdgeMove(axis: .y, from: 1, to: 0.9)) == nil)
}

@Test func aMoveThatShrinksAZoneBelowTheMinimumIsRejected() {
    #expect(Geometry.moving(three, EdgeMove(axis: .x, from: 0.5, to: 0.95)) == nil)
}

@Test func aMoveOnALineNoZoneHasIsRejected() {
    #expect(Geometry.moving(three, EdgeMove(axis: .x, from: 0.3, to: 0.4)) == nil)
}

@Test func aMissingZoneResolvesToTheNearestEarlierLetter() {
    let placed = two.map { PlacedZone($0, in: area, side: .top, size: 24) }
    #expect(placed.resolve("C")?.id == "B")
    #expect(placed.resolve("A")?.id == "A")
}

@Test func placedZonesShareEdgesAndReserveTheBar() {
    let placed = three.map { PlacedZone($0, in: area, side: .top, size: 24) }
    #expect(placed[0].full == CGRect(x: 3272, y: -81, width: 960, height: 1080))
    #expect(placed[0].bar == CGRect(x: 3272, y: -81, width: 960, height: 24))
    #expect(placed[0].content == CGRect(x: 3272, y: -57, width: 960, height: 1056))
    #expect(placed[1].full == CGRect(x: 4232, y: -81, width: 960, height: 540))
    #expect(placed[2].full == CGRect(x: 4232, y: 459, width: 960, height: 540))
    #expect(placed[2].bar == CGRect(x: 4232, y: 459, width: 960, height: 24))
    #expect(placed[2].content == CGRect(x: 4232, y: 483, width: 960, height: 516))
    #expect(placed.zone(at: CGPoint(x: 4232, y: 459))?.id == "C")
    #expect(placed.zone(at: CGPoint(x: 4231, y: 459))?.id == "A")
}

@Test func gestureTellsMovesFromResizesAndIgnoresJitter() {
    let old = CGRect(x: 100, y: 100, width: 500, height: 400)
    #expect(Geometry.gesture(from: old, to: CGRect(x: 102, y: 99, width: 501, height: 400)) == .unchanged)
    #expect(Geometry.gesture(from: old, to: CGRect(x: 300, y: 250, width: 500, height: 400)) == .moved)
    #expect(Geometry.gesture(from: old, to: CGRect(x: 100, y: 100, width: 620, height: 400)) == .resized)
}

@Test func aDoubleClickOnTheWindowThatResizesItIsAZoom() {
    let old = CGRect(x: 666, y: 53, width: 500, height: 400)
    let screen = CGRect(x: 0, y: 25, width: 1352, height: 823)
    #expect(Geometry.gesture(from: old, to: screen, doubleClick: CGPoint(x: 900, y: 60)) == .zoomed)
    #expect(Geometry.gesture(from: old, to: screen, doubleClick: CGPoint(x: 300, y: 60)) == .resized)
    #expect(Geometry.gesture(from: old, to: old.offsetBy(dx: -200, dy: 0), doubleClick: CGPoint(x: 900, y: 60)) == .moved)
}

@Test func aWindowDraggedFromInsideThatLandsAtAnotherSizeWasTiledByMacOS() {
    let old = CGRect(x: 100, y: 100, width: 600, height: 400)
    let tile = CGRect(x: 0, y: 25, width: 960, height: 1055)
    let wider = CGRect(x: 100, y: 100, width: 700, height: 400)
    #expect(Geometry.gesture(from: old, to: tile, dragged: Geometry.drags(old, from: CGPoint(x: 400, y: 107), to: CGPoint(x: 0, y: 500))) == .tiled)
    #expect(Geometry.gesture(from: old, to: wider, dragged: Geometry.drags(old, from: CGPoint(x: 400, y: 300), to: CGPoint(x: 405, y: 300))) == .resized)
    #expect(Geometry.gesture(from: old, to: wider, dragged: Geometry.drags(old, from: CGPoint(x: 702, y: 300), to: CGPoint(x: 802, y: 300))) == .resized)
    #expect(Geometry.gesture(from: old, to: old.offsetBy(dx: 300, dy: 0), dragged: true) == .moved)
}

@Test func draggingAWindowEdgeOnADividerMovesThatDivider() {
    let old = CGRect(x: 3272, y: -57, width: 960, height: 1056)
    let now = CGRect(x: 3272, y: -57, width: 1152, height: 1056)
    let moves = Geometry.edgeMoves(old: old, now: now, grabbed: CGPoint(x: 4234, y: 300), area: area, inset: Insets())
    #expect(moves == [EdgeMove(axis: .x, from: 0.5, to: 0.6)])
}

@Test func aTopEdgeMoveCountsTheBarAboveTheWindow() {
    let old = CGRect(x: 4232, y: 483, width: 960, height: 516)
    let now = CGRect(x: 4232, y: 375, width: 960, height: 624)
    let moves = Geometry.edgeMoves(old: old, now: now, grabbed: CGPoint(x: 4600, y: 481), area: area, inset: Insets(top: 24))
    #expect(moves == [EdgeMove(axis: .y, from: 0.5, to: 0.4)])
}

@Test func aRightEdgeMoveCountsTheBarBesideTheWindow() {
    let old = CGRect(x: 3272, y: -81, width: 790, height: 1080)
    let now = CGRect(x: 3272, y: -81, width: 982, height: 1080)
    let moves = Geometry.edgeMoves(old: old, now: now, grabbed: CGPoint(x: 4063, y: 300), area: area, inset: Insets(right: -170))
    #expect(moves == [EdgeMove(axis: .x, from: 0.5, to: 0.6)])
}

@Test func anEdgeThatMovedAwayFromThePointerIsNotADividerDrag() {
    let old = CGRect(x: 3272, y: -57, width: 960, height: 1056)
    let now = CGRect(x: 3272, y: -57, width: 1152, height: 1056)
    let moves = Geometry.edgeMoves(old: old, now: now, grabbed: CGPoint(x: 3700, y: 300), area: area, inset: Insets())
    #expect(moves.isEmpty)
}

@Test func aWindowInsideItsZoneKeepsItsPlaceAndOneArrivingIsCentered() {
    let zone = CGRect(x: 1000, y: 0, width: 960, height: 540)
    #expect(Geometry.arrive(CGRect(x: 1100, y: 50, width: 400, height: 300), in: zone, area: display) == CGRect(x: 1100, y: 50, width: 400, height: 300))
    #expect(Geometry.arrive(CGRect(x: 1700, y: 300, width: 400, height: 300), in: zone, area: display) == CGRect(x: 1560, y: 240, width: 400, height: 300))
    #expect(Geometry.arrive(CGRect(x: 0, y: 0, width: 400, height: 300), in: zone, area: display) == CGRect(x: 1280, y: 120, width: 400, height: 300))
    #expect(Geometry.arrive(CGRect(x: -1500, y: 600, width: 2000, height: 300), in: zone, area: display) == CGRect(x: 1000, y: 120, width: 2000, height: 300))
}

@Test func aBarOnEachSideTakesItsStripOfTheZoneAndLeavesTheRestToTheWindows() {
    let a = Zone(id: "A", x: 0, y: 0, w: 0.5, h: 1)
    let bottom = PlacedZone(a, in: area, side: .bottom, size: 24)
    #expect(bottom.bar == CGRect(x: 3272, y: 975, width: 960, height: 24))
    #expect(bottom.content == CGRect(x: 3272, y: -81, width: 960, height: 1056))
    let left = PlacedZone(a, in: area, side: .left, size: 170)
    #expect(left.bar == CGRect(x: 3272, y: -81, width: 170, height: 1080))
    #expect(left.content == CGRect(x: 3442, y: -81, width: 790, height: 1080))
    let right = PlacedZone(a, in: area, side: .right, size: 170)
    #expect(right.bar == CGRect(x: 4062, y: -81, width: 170, height: 1080))
    #expect(right.content == CGRect(x: 3272, y: -81, width: 790, height: 1080))
}

@Test func anOpenedSideBarGrowsFromItsZonesEdgeNeverWiderThanTheZone() {
    #expect(PlacedZone(Zone(id: "A", x: 0, y: 0, w: 0.5, h: 1), in: area, side: .right, size: 30).widened(to: 170)
        == CGRect(x: 4062, y: -81, width: 170, height: 1080))
    #expect(PlacedZone(Zone(id: "A", x: 0, y: 0, w: 0.05, h: 1), in: area, side: .left, size: 30).widened(to: 170)
        == CGRect(x: 3272, y: -81, width: 96, height: 1080))
}

@Test func aWindowNeverSlidesUnderASideBarAndAnOversizedOneOverflowsAwayFromIt() {
    let left = PlacedZone(Zone(id: "A", x: 0, y: 0, w: 0.5, h: 1), in: display, side: .left, size: 170).content
    #expect(Geometry.contain(CGRect(x: -300, y: 100, width: 400, height: 300), in: left, area: display)
        == CGRect(x: 170, y: 100, width: 400, height: 300))
    let right = PlacedZone(Zone(id: "A", x: 0, y: 0, w: 0.5, h: 1), in: display, side: .right, size: 170).content
    #expect(Geometry.arrive(CGRect(x: 0, y: 100, width: 1200, height: 300), in: right, area: display, centering: false)
        == CGRect(x: -410, y: 100, width: 1200, height: 300))
}

@Test func aWindowTallerOrWiderThanItsContentOverflowsAwayFromItsBarPastTheDisplayTopWhenItMust() {
    let below = PlacedZone(Zone(id: "B", x: 0, y: 0.5, w: 1, h: 0.5), in: display, side: .bottom, size: 22).content
    #expect(Geometry.arrive(CGRect(x: 0, y: 600, width: 400, height: 700), in: below, area: display, centering: false, side: .bottom)
        == CGRect(x: 0, y: 358, width: 400, height: 700))
    #expect(Geometry.contain(CGRect(x: 0, y: 600, width: 400, height: 700), in: below, area: display, side: .bottom)
        == CGRect(x: 0, y: 358, width: 400, height: 700))
    #expect(Geometry.arrive(CGRect(x: 0, y: 600, width: 400, height: 1200), in: below, area: display, centering: false, side: .bottom)
        == CGRect(x: 0, y: -142, width: 400, height: 1200))
    let above = PlacedZone(Zone(id: "A", x: 0, y: 0, w: 1, h: 0.5), in: display, side: .bottom, size: 22).content
    #expect(Geometry.arrive(CGRect(x: 0, y: 0, width: 400, height: 700), in: above, area: display, centering: false, side: .bottom)
        == CGRect(x: 0, y: -182, width: 400, height: 700))
    #expect(Geometry.contain(CGRect(x: 0, y: 100, width: 400, height: 700), in: above, area: display, side: .bottom)
        == CGRect(x: 0, y: -182, width: 400, height: 700))
    let middle = PlacedZone(Zone(id: "B", x: 1.0 / 3, y: 0, w: 1.0 / 3, h: 1), in: display, side: .right, size: 170).content
    #expect(Geometry.arrive(CGRect(x: 700, y: 100, width: 600, height: 300), in: middle, area: display, centering: false, side: .right)
        == CGRect(x: 510, y: 100, width: 600, height: 300))
    #expect(Geometry.contain(CGRect(x: 700, y: 100, width: 600, height: 300), in: middle, area: display, side: .right)
        == CGRect(x: 510, y: 100, width: 600, height: 300))
}

@Test func dividerLinesSkipTheStretchesUnderTheBars() {
    func lines(_ side: Side, _ size: CGFloat) -> [CGRect] {
        let placed = three.map { PlacedZone($0, in: area, side: side, size: size) }
        return Geometry.uncovered(Geometry.dividers(placed, in: area, thickness: 1), by: placed.map(\.bar))
    }
    #expect(lines(.top, 24) == [CGRect(x: 4232, y: -57, width: 1, height: 516), CGRect(x: 4232, y: 483, width: 1, height: 516)])
    #expect(lines(.left, 30) == [CGRect(x: 4262, y: 459, width: 930, height: 1)])
}

@Test func dividersDrawEachInnerLineOnceInsideTheZoneAfterItAndSkipTheDisplayEdges() {
    let threeZones = three.map { PlacedZone($0, in: area, side: .top, size: 24) }
    #expect(Geometry.dividers(threeZones, in: area, thickness: 1) == [
        CGRect(x: 4232, y: -81, width: 1, height: 1080),
        CGRect(x: 4232, y: 459, width: 960, height: 1),
    ])
    let twoZones = two.map { PlacedZone($0, in: area, side: .top, size: 24) }
    #expect(Geometry.dividers(twoZones, in: area, thickness: 1) == [CGRect(x: 4232, y: -81, width: 1, height: 1080)])
}

private let display = CGRect(x: 0, y: 0, width: 1920, height: 1080)

private let desk = CGRect(x: 0, y: 24, width: 1920, height: 1056)

@Test func aFreeWindowStopsAtADividerInsteadOfCrossingIntoTheNeighborZone() {
    let left = CGRect(x: 0, y: 24, width: 960, height: 1056)
    #expect(Geometry.contain(CGRect(x: 800, y: 100, width: 400, height: 300), in: left, area: desk)
        == CGRect(x: 560, y: 100, width: 400, height: 300))
    let topMiddle = CGRect(x: 640, y: 24, width: 640, height: 516)
    #expect(Geometry.contain(CGRect(x: 100, y: 400, width: 400, height: 300), in: topMiddle, area: desk)
        == CGRect(x: 640, y: 240, width: 400, height: 300))
}

@Test func aFreeWindowHangsPastTheDisplayEdgeWhileAPartStaysInside() {
    let left = CGRect(x: 0, y: 24, width: 960, height: 1056)
    #expect(Geometry.contain(CGRect(x: -300, y: 900, width: 400, height: 300), in: left, area: desk)
        == CGRect(x: -300, y: 900, width: 400, height: 300))
    #expect(Geometry.contain(CGRect(x: -500, y: 1050, width: 400, height: 300), in: left, area: desk)
        == CGRect(x: -320, y: 1000, width: 400, height: 300))
    #expect(Geometry.contain(CGRect(x: -500, y: -50, width: 50, height: 40), in: left, area: desk)
        == CGRect(x: 0, y: 24, width: 50, height: 40))
}

private let upper = CGRect(x: 455, y: 0, width: 1920, height: 1080)
private let lowerDisplay = CGRect(x: 0, y: 1080, width: 2954, height: 1662)
private let rightDisplay = CGRect(x: 2375, y: 0, width: 1920, height: 1080)
private let upperArea = CGRect(x: 455, y: 0, width: 1920, height: 1040)

@Test func aDisplayEdgeIsAWallAlongAZoneOnlyWhereAnotherDisplayBordersIt() {
    let wide = CGRect(x: 485, y: 0, width: 1336, height: 1040)
    #expect(Geometry.walls(wide, bounds: upper, others: [lowerDisplay, rightDisplay]) == Walls(left: false, right: true, bottom: true))
    #expect(Geometry.walls(wide, bounds: upper, others: [CGRect(x: -1465, y: 0, width: 1920, height: 1080), rightDisplay])
        == Walls(left: true, right: true, bottom: false))
    #expect(Geometry.walls(CGRect(x: 1851, y: 0, width: 524, height: 1040), bounds: upper, others: [CGRect(x: 0, y: 1080, width: 1800, height: 1000)])
        == Walls())
    #expect(Geometry.walls(wide, bounds: upper, others: [CGRect(x: 0, y: 1100, width: 2954, height: 1662), CGRect(x: 2400, y: 0, width: 1920, height: 1080)])
        == Walls())
}

@Test func aFreeWindowStopsAtADisplayEdgeThatBordersAnotherDisplayInsteadOfHangingIntoIt() {
    let left = CGRect(x: 485, y: 0, width: 1336, height: 1040)
    let right = CGRect(x: 1851, y: 0, width: 524, height: 1040)
    let walls = Walls(left: false, right: true, bottom: true)
    #expect(Geometry.contain(CGRect(x: 485, y: 424, width: 1336, height: 1040), in: left, area: upperArea, side: .left, walls: walls)
        == CGRect(x: 485, y: 0, width: 1336, height: 1040))
    #expect(Geometry.contain(CGRect(x: 2200, y: 100, width: 400, height: 300), in: right, area: upperArea, side: .left, walls: walls)
        == CGRect(x: 1975, y: 100, width: 400, height: 300))
    #expect(Geometry.contain(
        CGRect(x: 300, y: 100, width: 400, height: 300), in: CGRect(x: 455, y: 22, width: 1366, height: 1018), area: upperArea,
        walls: Walls(left: true, right: false, bottom: false)
    ) == CGRect(x: 455, y: 100, width: 400, height: 300))
}

@Test func aWindowWiderThanItsZoneOverflowsOnlyPastTheDisplayEdgeWhenItHasOne() {
    let right = CGRect(x: 960, y: 24, width: 960, height: 1056)
    #expect(Geometry.contain(CGRect(x: 700, y: 100, width: 1200, height: 300), in: right, area: desk)
        == CGRect(x: 960, y: 100, width: 1200, height: 300))
    let topMiddle = CGRect(x: 640, y: 24, width: 640, height: 516)
    #expect(Geometry.contain(CGRect(x: 300, y: -50, width: 900, height: 700), in: topMiddle, area: desk)
        == CGRect(x: 380, y: 24, width: 900, height: 700))
}

@Test func placingWithoutCenteringClampsAWindowThatFitsAndSendsAnOversizedOneToTheDisplayEdge() {
    let left = CGRect(x: 0, y: 24, width: 960, height: 1056)
    #expect(Geometry.arrive(CGRect(x: 900, y: 100, width: 400, height: 300), in: left, area: display, centering: false)
        == CGRect(x: 560, y: 100, width: 400, height: 300))
    #expect(Geometry.arrive(CGRect(x: 0, y: 100, width: 1200, height: 800), in: left, area: display, centering: false)
        == CGRect(x: -240, y: 100, width: 1200, height: 800))
}

@Test func anOversizedWindowArrivesOverflowingPastTheDisplayEdgeOfItsZone() {
    let left = CGRect(x: 0, y: 24, width: 960, height: 1056)
    #expect(Geometry.arrive(CGRect(x: 1200, y: 100, width: 1200, height: 800), in: left, area: display)
        == CGRect(x: -240, y: 152, width: 1200, height: 800))
    #expect(Geometry.arrive(CGRect(x: 100, y: 100, width: 1200, height: 800), in: left, area: display)
        == CGRect(x: -240, y: 100, width: 1200, height: 800))
}

@Test func centeringPutsAFittingAxisInTheMiddleAndAnOversizedOnePastTheDisplayEdge() {
    let left = CGRect(x: 0, y: 24, width: 960, height: 1056)
    #expect(Geometry.center(CGRect(x: 700, y: 900, width: 400, height: 300), in: left, area: display)
        == CGRect(x: 280, y: 402, width: 400, height: 300))
    #expect(Geometry.center(CGRect(x: 700, y: 900, width: 1200, height: 800), in: left, area: display)
        == CGRect(x: -240, y: 152, width: 1200, height: 800))
}

@Test func compactTabsShrinkEveryInactiveTabToItsIconAndGiveTheRestToTheActiveOne() {
    #expect(Geometry.tabWidths([false, true, false], compact: true, space: 400, icon: 30, maximum: 240) == [30, 240, 30])
    #expect(Geometry.tabWidths([false, true, false], compact: true, space: 200, icon: 30, maximum: 240) == [30, 140, 30])
    #expect(Geometry.tabWidths([false, true, false], compact: false, space: 400, icon: 30, maximum: 240) == [133, 133, 133])
}

@Test func aSizeRoundedUpPastTheRequestIsAskedAgainShortenedByTheOvershoot() {
    #expect(Geometry.retry(CGSize(width: 1049, height: 484), got: CGSize(width: 1049, height: 490)) == CGSize(width: 1049, height: 478))
    #expect(Geometry.retry(CGSize(width: 800, height: 484), got: CGSize(width: 806, height: 470)) == CGSize(width: 794, height: 470))
    #expect(Geometry.retry(CGSize(width: 800, height: 484), got: CGSize(width: 802, height: 475)) == nil)
}

@Test func splittingHalvesAZoneAndLettersZonesInReadingOrder() {
    #expect(matches(Geometry.splitting(two, at: 1, along: .y), three))
    #expect(matches(Geometry.splitting([Zone(id: "A", x: 0, y: 0, w: 1, h: 1)], at: 0, along: .x), two))
}

@Test func splitsBelowTheMinimumSizeOrAboveTheZoneLimitAreRejected() {
    #expect(Geometry.splitting([Zone(id: "A", x: 0, y: 0, w: 0.15, h: 1)], at: 0, along: .x) == nil)
    let nine = (0..<9).map { Zone(id: String(UnicodeScalar(UInt8(65 + $0))), x: Double($0) / 9, y: 0, w: 1.0 / 9, h: 1) }
    #expect(Geometry.splitting(nine, at: 0, along: .y) == nil)
}

@Test func editingALayoutKeepsEachZonesBarSideAndBothHalvesOfASplitInheritIt() {
    let sided = [Zone(id: "A", x: 0, y: 0, w: 0.5, h: 1), Zone(id: "B", x: 0.5, y: 0, w: 0.5, h: 1, tabsAt: .left)]
    #expect(Geometry.splitting(sided, at: 1, along: .y)?.map(\.tabsAt) == [nil, .left, .left])
    #expect(Geometry.moving(sided, EdgeMove(axis: .x, from: 0.5, to: 0.6))?.map(\.tabsAt) == [nil, .left])
    let corner = [Zone(id: "A", x: 0, y: 0, w: 0.5, h: 0.5), sided[1], Zone(id: "C", x: 0, y: 0.5, w: 0.5, h: 0.5, tabsAt: .right)]
    #expect(Geometry.removing(corner, at: 0)?.map { "\($0.id) \($0.tabsAt?.rawValue ?? "-")" } == ["A right", "B left"])
}

@Test func removingAZoneGivesItsSpaceToTheNeighborsAlongAWholeSide() {
    #expect(matches(Geometry.removing(three, at: 0), rows))
    #expect(matches(Geometry.removing(three, at: 1), two))
}

@Test func theLastZoneCannotBeRemoved() {
    #expect(Geometry.removing([Zone(id: "A", x: 0, y: 0, w: 1, h: 1)], at: 0) == nil)
}
