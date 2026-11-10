import CoreGraphics

enum Side: String, Codable, CaseIterable {
    case top, bottom, left, right

    var vertical: Bool { self == .left || self == .right }

    var name: String {
        switch self {
        case .top: "Arriba"
        case .bottom: "Abajo"
        case .left: "Izquierda"
        case .right: "Derecha"
        }
    }
}

struct Zone: Codable, Equatable {
    var id: String
    var x: Double
    var y: Double
    var w: Double
    var h: Double
    var tabsAt: Side?

    init(id: String, x: Double, y: Double, w: Double, h: Double, tabsAt: Side? = nil) {
        self.id = id
        self.x = x
        self.y = y
        self.w = w
        self.h = h
        self.tabsAt = tabsAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        x = try container.decode(Double.self, forKey: .x)
        y = try container.decode(Double.self, forKey: .y)
        w = try container.decode(Double.self, forKey: .w)
        h = try container.decode(Double.self, forKey: .h)
        tabsAt = (try? container.decodeIfPresent(Side.self, forKey: .tabsAt)) ?? nil
    }
}

struct Layout: Codable, Equatable {
    var name: String
    var zones: [Zone]

    static let single = Layout(name: "Una columna", zones: [Zone(id: "A", x: 0, y: 0, w: 1, h: 1)])
}

struct Insets: Equatable {
    var left: CGFloat = 0
    var top: CGFloat = 0
    var right: CGFloat = 0
    var bottom: CGFloat = 0
}

struct Walls: Equatable {
    var left = false
    var right = false
    var bottom = false
}

struct PlacedZone: Equatable {
    let id: String
    let side: Side
    let full: CGRect
    let bar: CGRect
    let content: CGRect

    init(_ zone: Zone, in area: CGRect, side: Side, size: CGFloat) {
        let x1 = (area.minX + zone.x * area.width).rounded()
        let y1 = (area.minY + zone.y * area.height).rounded()
        let x2 = (area.minX + (zone.x + zone.w) * area.width).rounded()
        let y2 = (area.minY + (zone.y + zone.h) * area.height).rounded()
        let full = CGRect(x: x1, y: y1, width: x2 - x1, height: y2 - y1)
        id = zone.id
        self.side = side
        self.full = full
        switch side {
        case .top:
            bar = CGRect(x: full.minX, y: full.minY, width: full.width, height: size)
            content = CGRect(x: full.minX, y: full.minY + size, width: full.width, height: full.height - size)
        case .bottom:
            bar = CGRect(x: full.minX, y: full.maxY - size, width: full.width, height: size)
            content = CGRect(x: full.minX, y: full.minY, width: full.width, height: full.height - size)
        case .left:
            bar = CGRect(x: full.minX, y: full.minY, width: size, height: full.height)
            content = CGRect(x: full.minX + size, y: full.minY, width: full.width - size, height: full.height)
        case .right:
            bar = CGRect(x: full.maxX - size, y: full.minY, width: size, height: full.height)
            content = CGRect(x: full.minX, y: full.minY, width: full.width - size, height: full.height)
        }
    }

    var margins: Insets {
        Insets(
            left: content.minX - full.minX, top: content.minY - full.minY,
            right: content.maxX - full.maxX, bottom: content.maxY - full.maxY
        )
    }

    func widened(to size: CGFloat) -> CGRect {
        guard side.vertical else { return bar }
        let width = min(size, full.width)
        return CGRect(x: side == .left ? full.minX : full.maxX - width, y: bar.minY, width: width, height: bar.height)
    }
}

extension Array where Element == PlacedZone {
    func resolve(_ id: String) -> PlacedZone? {
        first { $0.id == id } ?? filter { $0.id < id }.max { $0.id < $1.id } ?? first
    }

    func zone(at point: CGPoint) -> PlacedZone? {
        first { $0.full.contains(point) }
    }
}

enum Axis: Equatable {
    case x, y
}

struct EdgeMove: Equatable {
    let axis: Axis
    let from: Double
    let to: Double
}

enum Gesture: Equatable {
    case unchanged, moved, resized, zoomed, tiled
}

extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

enum Geometry {
    static let edgeTolerance = 0.01
    static let minimumFraction = 0.1
    static let maximumZones = 9
    static let pixelTolerance: CGFloat = 2
    static let grab: CGFloat = 12
    static let visible: CGFloat = 80

    static func same(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= pixelTolerance && abs(a.minY - b.minY) <= pixelTolerance
            && abs(a.width - b.width) <= pixelTolerance && abs(a.height - b.height) <= pixelTolerance
    }

    static func gesture(from old: CGRect, to now: CGRect, doubleClick: CGPoint? = nil, dragged: Bool = false) -> Gesture {
        if same(old, now) { return .unchanged }
        guard abs(old.width - now.width) > pixelTolerance || abs(old.height - now.height) > pixelTolerance else { return .moved }
        if doubleClick.map(old.contains) == true { return .zoomed }
        return dragged ? .tiled : .resized
    }

    static func drags(_ frame: CGRect, from down: CGPoint, to up: CGPoint) -> Bool {
        frame.contains(down) && hypot(up.x - down.x, up.y - down.y) > grab
    }

    static func walls(_ zone: CGRect, bounds: CGRect, others: [CGRect]) -> Walls {
        func at(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) <= pixelTolerance }
        func alongY(_ other: CGRect) -> Bool { min(other.maxY, zone.maxY) - max(other.minY, zone.minY) > pixelTolerance }
        func alongX(_ other: CGRect) -> Bool { min(other.maxX, zone.maxX) - max(other.minX, zone.minX) > pixelTolerance }
        return Walls(
            left: others.contains { at($0.maxX, bounds.minX) && alongY($0) },
            right: others.contains { at($0.minX, bounds.maxX) && alongY($0) },
            bottom: others.contains { at($0.minY, bounds.maxY) && alongX($0) }
        )
    }

    private static func awayFromBar(_ frame: CGRect, in zone: CGRect, side: Side) -> CGRect {
        var x = frame.minX
        var y = frame.minY
        switch side {
        case .left: x = max(x, zone.minX)
        case .right: x = min(x, zone.maxX - frame.width)
        case .bottom: y = min(y, zone.maxY - frame.height)
        case .top: break
        }
        return CGRect(x: x, y: y, width: frame.width, height: frame.height)
    }

    static func contain(_ frame: CGRect, in zone: CGRect, area: CGRect, side: Side = .top, walls: Walls = Walls()) -> CGRect {
        let width = min(visible, frame.width)
        let height = min(visible, frame.height)
        let leftDivider = zone.minX > area.minX + pixelTolerance || walls.left
        let rightDivider = zone.maxX < area.maxX - pixelTolerance || walls.right
        let bottomDivider = zone.maxY < area.maxY - pixelTolerance || walls.bottom
        let lowestX = leftDivider ? zone.minX : zone.minX + width - frame.width
        let highestX = rightDivider ? zone.maxX - frame.width : zone.maxX - width
        let x = lowestX <= highestX
            ? min(max(frame.minX, lowestX), highestX)
            : min(max(frame.minX, highestX), lowestX)
        let highestY = bottomDivider ? zone.maxY - frame.height : zone.maxY - height
        let y = max(min(max(frame.minY, zone.minY), highestY), zone.minY)
        return awayFromBar(CGRect(x: x, y: y, width: frame.width, height: frame.height), in: zone, side: side)
    }

    static func arrive(_ frame: CGRect, in zone: CGRect, area: CGRect, centering: Bool = true, side: Side = .top) -> CGRect {
        let outside = centering && !zone.contains(frame.center)
        let x: CGFloat
        let y: CGFloat
        if frame.width > zone.width {
            let againstLeft = zone.minX <= area.minX + pixelTolerance && zone.maxX < area.maxX - pixelTolerance
            x = againstLeft ? zone.maxX - frame.width : zone.minX
        } else {
            let start = outside ? (zone.midX - frame.width / 2).rounded() : frame.minX
            x = min(max(start, zone.minX), zone.maxX - frame.width)
        }
        if frame.height > zone.height {
            y = zone.minY
        } else {
            let start = outside ? (zone.midY - frame.height / 2).rounded() : frame.minY
            y = min(max(start, zone.minY), zone.maxY - frame.height)
        }
        return awayFromBar(CGRect(x: x, y: y, width: frame.width, height: frame.height), in: zone, side: side)
    }

    static func center(_ frame: CGRect, in zone: CGRect, area: CGRect, side: Side = .top) -> CGRect {
        let origin = CGPoint(x: (zone.midX - frame.width / 2).rounded(), y: (zone.midY - frame.height / 2).rounded())
        return arrive(CGRect(origin: origin, size: frame.size), in: zone, area: area, centering: false, side: side)
    }

    static func tabWidths(_ active: [Bool], compact: Bool, space: CGFloat, icon: CGFloat, maximum: CGFloat) -> [CGFloat] {
        guard !active.isEmpty else { return [] }
        let even = min(maximum, (space / CGFloat(active.count)).rounded(.down))
        let wide = max(icon, min(maximum, space - icon * CGFloat(active.count - 1)))
        return active.map { !compact ? even : $0 ? wide : icon }
    }

    static func retry(_ asked: CGSize, got: CGSize) -> CGSize? {
        let wider = got.width > asked.width + pixelTolerance
        let taller = got.height > asked.height + pixelTolerance
        guard wider || taller else { return nil }
        return CGSize(
            width: wider ? asked.width - (got.width - asked.width) : got.width,
            height: taller ? asked.height - (got.height - asked.height) : got.height
        )
    }

    static func dividers(_ zones: [PlacedZone], in area: CGRect, thickness: CGFloat) -> [CGRect] {
        var vertical: [CGFloat: [ClosedRange<CGFloat>]] = [:]
        var horizontal: [CGFloat: [ClosedRange<CGFloat>]] = [:]
        for zone in zones {
            let full = zone.full
            if full.minX > area.minX + pixelTolerance { vertical[full.minX, default: []].append(full.minY...full.maxY) }
            if full.maxX < area.maxX - pixelTolerance { vertical[full.maxX, default: []].append(full.minY...full.maxY) }
            if full.minY > area.minY + pixelTolerance { horizontal[full.minY, default: []].append(full.minX...full.maxX) }
            if full.maxY < area.maxY - pixelTolerance { horizontal[full.maxY, default: []].append(full.minX...full.maxX) }
        }
        var rects: [CGRect] = []
        for (x, spans) in vertical {
            for span in merge(spans) {
                rects.append(CGRect(x: x, y: span.lowerBound, width: thickness, height: span.upperBound - span.lowerBound))
            }
        }
        for (y, spans) in horizontal {
            for span in merge(spans) {
                rects.append(CGRect(x: span.lowerBound, y: y, width: span.upperBound - span.lowerBound, height: thickness))
            }
        }
        return rects.sorted { ($0.minX, $0.minY) < ($1.minX, $1.minY) }
    }

    static func uncovered(_ lines: [CGRect], by holes: [CGRect]) -> [CGRect] {
        lines.flatMap { line -> [CGRect] in
            let across = line.width > line.height
            var spans = [across ? (line.minX, line.maxX) : (line.minY, line.maxY)]
            for hole in holes {
                let spansLine = across
                    ? hole.minY <= line.minY && hole.maxY >= line.maxY
                    : hole.minX <= line.minX && hole.maxX >= line.maxX
                guard spansLine else { continue }
                let from = across ? hole.minX : hole.minY
                let to = across ? hole.maxX : hole.maxY
                spans = spans.flatMap { span -> [(CGFloat, CGFloat)] in
                    if to <= span.0 || from >= span.1 { return [span] }
                    return [(span.0, from), (to, span.1)].filter { $0.1 - $0.0 > pixelTolerance }
                }
            }
            return spans.map { span in
                across
                    ? CGRect(x: span.0, y: line.minY, width: span.1 - span.0, height: line.height)
                    : CGRect(x: line.minX, y: span.0, width: line.width, height: span.1 - span.0)
            }
        }
    }

    private static func merge(_ spans: [ClosedRange<CGFloat>]) -> [ClosedRange<CGFloat>] {
        var merged: [ClosedRange<CGFloat>] = []
        for span in spans.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = merged.last, span.lowerBound <= last.upperBound + pixelTolerance {
                merged[merged.count - 1] = last.lowerBound...max(last.upperBound, span.upperBound)
            } else {
                merged.append(span)
            }
        }
        return merged
    }

    static func moving(_ zones: [Zone], _ move: EdgeMove) -> [Zone]? {
        guard move.from > edgeTolerance, move.from < 1 - edgeTolerance else { return nil }
        let to = (move.to * 10000).rounded() / 10000
        let position: WritableKeyPath<Zone, Double> = move.axis == .x ? \.x : \.y
        let size: WritableKeyPath<Zone, Double> = move.axis == .x ? \.w : \.h
        var result = zones
        var hit = false
        for i in result.indices {
            let start = result[i][keyPath: position]
            let end = start + result[i][keyPath: size]
            if abs(start - move.from) < edgeTolerance {
                result[i][keyPath: position] = to
                result[i][keyPath: size] = end - to
                hit = true
            } else if abs(end - move.from) < edgeTolerance {
                result[i][keyPath: size] = to - start
                hit = true
            }
            if result[i][keyPath: size] < minimumFraction { return nil }
        }
        return hit ? result : nil
    }

    static func splitting(_ zones: [Zone], at index: Int, along axis: Axis) -> [Zone]? {
        guard zones.indices.contains(index), zones.count < maximumZones else { return nil }
        let position: WritableKeyPath<Zone, Double> = axis == .x ? \.x : \.y
        let size: WritableKeyPath<Zone, Double> = axis == .x ? \.w : \.h
        let half = (zones[index][keyPath: size] / 2 * 10000).rounded() / 10000
        guard half >= minimumFraction else { return nil }
        var result = zones
        var second = zones[index]
        second[keyPath: position] += half
        second[keyPath: size] -= half
        result[index][keyPath: size] = half
        result.append(second)
        return relabel(result)
    }

    static func removing(_ zones: [Zone], at index: Int) -> [Zone]? {
        guard zones.count > 1, zones.indices.contains(index) else { return nil }
        let gone = zones[index]
        var rest = zones
        rest.remove(at: index)
        for (axis, after) in [(Axis.x, true), (.x, false), (.y, true), (.y, false)] {
            let position: WritableKeyPath<Zone, Double> = axis == .x ? \.x : \.y
            let size: WritableKeyPath<Zone, Double> = axis == .x ? \.w : \.h
            let across: KeyPath<Zone, Double> = axis == .x ? \.y : \.x
            let span: KeyPath<Zone, Double> = axis == .x ? \.h : \.w
            let edge = after ? gone[keyPath: position] + gone[keyPath: size] : gone[keyPath: position]
            let start = gone[keyPath: across]
            let end = start + gone[keyPath: span]
            let neighbors = rest.indices.filter { i in
                let zone = rest[i]
                let side = after ? zone[keyPath: position] : zone[keyPath: position] + zone[keyPath: size]
                return abs(side - edge) < edgeTolerance && zone[keyPath: across] > start - edgeTolerance
                    && zone[keyPath: across] + zone[keyPath: span] < end + edgeTolerance
            }
            let covered = neighbors.reduce(0) { $0 + rest[$1][keyPath: span] }
            guard !neighbors.isEmpty, abs(covered - gone[keyPath: span]) < edgeTolerance else { continue }
            for i in neighbors {
                if after { rest[i][keyPath: position] = gone[keyPath: position] }
                rest[i][keyPath: size] += gone[keyPath: size]
            }
            return relabel(rest)
        }
        return nil
    }

    static func relabel(_ zones: [Zone]) -> [Zone] {
        let ordered = zones.sorted { a, b in
            let rowA = (a.y * 1000).rounded()
            let rowB = (b.y * 1000).rounded()
            return rowA != rowB ? rowA < rowB : a.x < b.x
        }
        return ordered.enumerated().map { index, zone in
            var zone = zone
            zone.id = String(UnicodeScalar(UInt8(65 + index)))
            return zone
        }
    }

    static func edgeMoves(old: CGRect, now: CGRect, grabbed: CGPoint, area: CGRect, inset: Insets) -> [EdgeMove] {
        var moves: [EdgeMove] = []
        func add(_ axis: Axis, _ before: CGFloat, _ after: CGFloat, _ pointer: CGFloat, _ offset: CGFloat) {
            guard abs(before - after) > pixelTolerance, abs(pointer - before) <= grab else { return }
            let base = axis == .x ? area.minX : area.minY
            let length = axis == .x ? area.width : area.height
            moves.append(EdgeMove(
                axis: axis,
                from: Double((before - offset - base) / length),
                to: Double((after - offset - base) / length)
            ))
        }
        add(.x, old.minX, now.minX, grabbed.x, inset.left)
        add(.x, old.maxX, now.maxX, grabbed.x, inset.right)
        add(.y, old.minY, now.minY, grabbed.y, inset.top)
        add(.y, old.maxY, now.maxY, grabbed.y, inset.bottom)
        return moves
    }
}
