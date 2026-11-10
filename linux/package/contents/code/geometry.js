var edgeTolerance = 0.01;
var minimumFraction = 0.1;
var maximumZones = 9;
var pixelTolerance = 2;
var grab = 12;
var visible = 80;

function rect(x, y, width, height) {
    return { x: x, y: y, width: width, height: height };
}

function maxX(r) { return r.x + r.width; }
function maxY(r) { return r.y + r.height; }
function midX(r) { return r.x + r.width / 2; }
function midY(r) { return r.y + r.height / 2; }
function center(r) { return { x: midX(r), y: midY(r) }; }

function contains(r, point) {
    return point.x >= r.x && point.x < maxX(r) && point.y >= r.y && point.y < maxY(r);
}

function covers(a, b) {
    return Math.min(maxX(a), maxX(b)) - Math.max(a.x, b.x) > pixelTolerance
        && Math.min(maxY(a), maxY(b)) - Math.max(a.y, b.y) > pixelTolerance;
}

function visiblePart(r, windows, along) {
    var start = along ? r.y : r.x;
    var spans = [[start, start + (along ? r.height : r.width)]];
    windows.forEach(function (w) {
        if (!covers(w, r)) return;
        var from = Math.floor(along ? w.y : w.x);
        var to = Math.ceil(along ? maxY(w) : maxX(w));
        spans = [].concat.apply([], spans.map(function (s) {
            if (to <= s[0] || from >= s[1]) return [s];
            return [[s[0], from], [to, s[1]]].filter(function (p) { return p[1] > p[0]; });
        }));
    });
    var longest = spans.reduce(function (best, s) { return !best || s[1] - s[0] > best[1] - best[0] ? s : best; }, null);
    if (!longest || longest[1] - longest[0] < (along ? r.width : r.height)) return null;
    return along ? rect(r.x, longest[0], r.width, longest[1] - longest[0]) : rect(longest[0], r.y, longest[1] - longest[0], r.height);
}

function zone(id, x, y, w, h) {
    return { id: id, x: x, y: y, w: w, h: h };
}

function vertical(side) {
    return side === "left" || side === "right";
}

function split(full, side, size) {
    var x = full.x, y = full.y, w = full.width, h = full.height;
    if (side === "bottom") return { bar: rect(x, y + h - size, w, size), content: rect(x, y, w, h - size) };
    if (side === "left") return { bar: rect(x, y, size, h), content: rect(x + size, y, w - size, h) };
    if (side === "right") return { bar: rect(x + w - size, y, size, h), content: rect(x, y, w - size, h) };
    return { bar: rect(x, y, w, size), content: rect(x, y + size, w, h - size) };
}

function place(z, area, side, size) {
    var x1 = Math.round(area.x + z.x * area.width);
    var y1 = Math.round(area.y + z.y * area.height);
    var x2 = Math.round(area.x + (z.x + z.w) * area.width);
    var y2 = Math.round(area.y + (z.y + z.h) * area.height);
    var full = rect(x1, y1, x2 - x1, y2 - y1);
    var parts = split(full, side, size);
    return { id: z.id, side: side, full: full, bar: parts.bar, content: parts.content };
}

function margins(placed) {
    return {
        left: placed.content.x - placed.full.x,
        top: placed.content.y - placed.full.y,
        right: maxX(placed.content) - maxX(placed.full),
        bottom: maxY(placed.content) - maxY(placed.full)
    };
}

function widened(placed, side, size) {
    if (!vertical(side)) return placed.bar;
    var width = Math.min(size, placed.full.width);
    var x = side === "left" ? placed.full.x : maxX(placed.full) - width;
    return rect(x, placed.bar.y, width, placed.bar.height);
}

function resolve(placed, id) {
    var exact = placed.find(function (p) { return p.id === id; });
    if (exact) return exact;
    var earlier = placed.filter(function (p) { return p.id < id; });
    if (earlier.length) return earlier.reduce(function (a, b) { return b.id > a.id ? b : a; });
    return placed.length ? placed[0] : null;
}

function zoneAt(placed, point) {
    return placed.find(function (p) { return contains(p.full, point); }) || null;
}

function same(a, b, tolerance) {
    var t = tolerance === undefined ? pixelTolerance : tolerance;
    return Math.abs(a.x - b.x) <= t && Math.abs(a.y - b.y) <= t && Math.abs(a.width - b.width) <= t && Math.abs(a.height - b.height) <= t;
}

function sameSize(a, b) {
    return Math.abs(a.width - b.width) <= pixelTolerance && Math.abs(a.height - b.height) <= pixelTolerance;
}

function gesture(old, now) {
    if (same(old, now)) return "unchanged";
    if (sameSize(old, now)) return "moved";
    return "resized";
}

function awayFromBar(placed, z, side) {
    var x = placed.x;
    var y = placed.y;
    if (side === "left") x = Math.max(x, z.x);
    if (side === "right") x = Math.min(x, maxX(z) - placed.width);
    if (side === "bottom") y = Math.min(y, maxY(z) - placed.height);
    return rect(x, y, placed.width, placed.height);
}

function walls(z, bounds, others) {
    function at(a, b) { return Math.abs(a - b) <= pixelTolerance; }
    function alongY(o) { return Math.min(maxY(o), maxY(z)) - Math.max(o.y, z.y) > pixelTolerance; }
    function alongX(o) { return Math.min(maxX(o), maxX(z)) - Math.max(o.x, z.x) > pixelTolerance; }
    return {
        left: others.some(function (o) { return at(maxX(o), bounds.x) && alongY(o); }),
        right: others.some(function (o) { return at(o.x, maxX(bounds)) && alongY(o); }),
        bottom: others.some(function (o) { return at(o.y, maxY(bounds)) && alongX(o); })
    };
}

function contain(frame, z, area, side, beyond) {
    var wall = beyond || {};
    var width = Math.min(visible, frame.width);
    var height = Math.min(visible, frame.height);
    var leftDivider = z.x > area.x + pixelTolerance || wall.left;
    var rightDivider = maxX(z) < maxX(area) - pixelTolerance || wall.right;
    var bottomDivider = maxY(z) < maxY(area) - pixelTolerance || wall.bottom;
    var lowestX = leftDivider ? z.x : z.x + width - frame.width;
    var highestX = rightDivider ? maxX(z) - frame.width : maxX(z) - width;
    var x = lowestX <= highestX
        ? Math.min(Math.max(frame.x, lowestX), highestX)
        : Math.min(Math.max(frame.x, highestX), lowestX);
    var highestY = bottomDivider ? maxY(z) - frame.height : maxY(z) - height;
    var y = Math.max(Math.min(Math.max(frame.y, z.y), highestY), z.y);
    return awayFromBar(rect(x, y, frame.width, frame.height), z, side);
}

function arrive(frame, z, area, centering, side) {
    var outside = centering !== false && !contains(z, center(frame));
    var x;
    var y;
    if (frame.width > z.width) {
        var againstLeft = z.x <= area.x + pixelTolerance && maxX(z) < maxX(area) - pixelTolerance;
        x = againstLeft ? maxX(z) - frame.width : z.x;
    } else {
        var startX = outside ? Math.round(midX(z) - frame.width / 2) : frame.x;
        x = Math.min(Math.max(startX, z.x), maxX(z) - frame.width);
    }
    if (frame.height > z.height) {
        y = z.y;
    } else {
        var startY = outside ? Math.round(midY(z) - frame.height / 2) : frame.y;
        y = Math.min(Math.max(startY, z.y), maxY(z) - frame.height);
    }
    return awayFromBar(rect(x, y, frame.width, frame.height), z, side);
}

function centered(frame, z, area, side) {
    var origin = rect(Math.round(midX(z) - frame.width / 2), Math.round(midY(z) - frame.height / 2), frame.width, frame.height);
    return arrive(origin, z, area, false, side);
}

function tabWidths(active, compact, space, icon, maximum) {
    if (!active.length) return [];
    var even = Math.min(maximum, Math.floor(space / active.length));
    var wide = Math.max(icon, Math.min(maximum, space - icon * (active.length - 1)));
    return active.map(function (a) { return !compact ? even : a ? wide : icon; });
}

function merge(spans) {
    var merged = [];
    spans.slice().sort(function (a, b) { return a[0] - b[0]; }).forEach(function (span) {
        var last = merged[merged.length - 1];
        if (last && span[0] <= last[1] + pixelTolerance) {
            last[1] = Math.max(last[1], span[1]);
        } else {
            merged.push([span[0], span[1]]);
        }
    });
    return merged;
}

function dividers(placed, area, thickness) {
    var vertical = {};
    var horizontal = {};
    function add(map, key, span) {
        (map[key] = map[key] || []).push(span);
    }
    placed.forEach(function (p) {
        var f = p.full;
        if (f.x > area.x + pixelTolerance) add(vertical, f.x, [f.y, maxY(f)]);
        if (maxX(f) < maxX(area) - pixelTolerance) add(vertical, maxX(f), [f.y, maxY(f)]);
        if (f.y > area.y + pixelTolerance) add(horizontal, f.y, [f.x, maxX(f)]);
        if (maxY(f) < maxY(area) - pixelTolerance) add(horizontal, maxY(f), [f.x, maxX(f)]);
    });
    var rects = [];
    Object.keys(vertical).forEach(function (key) {
        merge(vertical[key]).forEach(function (s) { rects.push(rect(Number(key), s[0], thickness, s[1] - s[0])); });
    });
    Object.keys(horizontal).forEach(function (key) {
        merge(horizontal[key]).forEach(function (s) { rects.push(rect(s[0], Number(key), s[1] - s[0], thickness)); });
    });
    return rects.sort(function (a, b) { return a.x !== b.x ? a.x - b.x : a.y - b.y; });
}

function uncovered(lines, holes) {
    var result = [];
    lines.forEach(function (line) {
        var across = line.width > line.height;
        var start = across ? line.x : line.y;
        var spans = [[start, start + (across ? line.width : line.height)]];
        holes.forEach(function (hole) {
            if (across ? hole.y > line.y || maxY(hole) < maxY(line) : hole.x > line.x || maxX(hole) < maxX(line)) return;
            var from = across ? hole.x : hole.y;
            var to = across ? maxX(hole) : maxY(hole);
            spans = [].concat.apply([], spans.map(function (s) {
                if (to <= s[0] || from >= s[1]) return [s];
                return [[s[0], from], [to, s[1]]].filter(function (p) { return p[1] - p[0] > pixelTolerance; });
            }));
        });
        spans.forEach(function (s) {
            result.push(across ? rect(s[0], line.y, s[1] - s[0], line.height) : rect(line.x, s[0], line.width, s[1] - s[0]));
        });
    });
    return result;
}

function copy(zones) {
    return zones.map(function (z) {
        var made = zone(z.id, z.x, z.y, z.w, z.h);
        if (z.tabsAt) made.tabsAt = z.tabsAt;
        return made;
    });
}

function moving(zones, move) {
    if (!(move.from > edgeTolerance && move.from < 1 - edgeTolerance)) return null;
    var to = Math.round(move.to * 10000) / 10000;
    var position = move.axis === "x" ? "x" : "y";
    var size = move.axis === "x" ? "w" : "h";
    var result = copy(zones);
    var hit = false;
    for (var i = 0; i < result.length; i++) {
        var start = result[i][position];
        var end = start + result[i][size];
        if (Math.abs(start - move.from) < edgeTolerance) {
            result[i][position] = to;
            result[i][size] = end - to;
            hit = true;
        } else if (Math.abs(end - move.from) < edgeTolerance) {
            result[i][size] = to - start;
            hit = true;
        }
        if (result[i][size] < minimumFraction) return null;
    }
    return hit ? result : null;
}

function splitting(zones, index, axis) {
    if (index < 0 || index >= zones.length || zones.length >= maximumZones) return null;
    var position = axis === "x" ? "x" : "y";
    var size = axis === "x" ? "w" : "h";
    var half = Math.round(zones[index][size] / 2 * 10000) / 10000;
    if (half < minimumFraction) return null;
    var result = copy(zones);
    var second = copy([zones[index]])[0];
    second[position] += half;
    second[size] -= half;
    result[index][size] = half;
    result.push(second);
    return relabel(result);
}

function removing(zones, index) {
    if (zones.length <= 1 || index < 0 || index >= zones.length) return null;
    var gone = zones[index];
    var sides = [["x", true], ["x", false], ["y", true], ["y", false]];
    for (var s = 0; s < sides.length; s++) {
        var rest = copy(zones);
        rest.splice(index, 1);
        var axis = sides[s][0];
        var after = sides[s][1];
        var position = axis === "x" ? "x" : "y";
        var size = axis === "x" ? "w" : "h";
        var across = axis === "x" ? "y" : "x";
        var span = axis === "x" ? "h" : "w";
        var edge = after ? gone[position] + gone[size] : gone[position];
        var start = gone[across];
        var end = start + gone[span];
        var neighbors = [];
        rest.forEach(function (z, i) {
            var side = after ? z[position] : z[position] + z[size];
            if (Math.abs(side - edge) < edgeTolerance && z[across] > start - edgeTolerance
                && z[across] + z[span] < end + edgeTolerance) neighbors.push(i);
        });
        var covered = neighbors.reduce(function (sum, i) { return sum + rest[i][span]; }, 0);
        if (!neighbors.length || Math.abs(covered - gone[span]) >= edgeTolerance) continue;
        neighbors.forEach(function (i) {
            if (after) rest[i][position] = gone[position];
            rest[i][size] += gone[size];
        });
        return relabel(rest);
    }
    return null;
}

function relabel(zones) {
    var ordered = copy(zones).sort(function (a, b) {
        var rowA = Math.round(a.y * 1000);
        var rowB = Math.round(b.y * 1000);
        return rowA !== rowB ? rowA - rowB : a.x - b.x;
    });
    return ordered.map(function (z, index) {
        z.id = String.fromCharCode(65 + index);
        return z;
    });
}

function edgeMoves(old, now, grabbed, area, inset) {
    var moves = [];
    function add(axis, before, after, pointer, offset) {
        if (!(Math.abs(before - after) > pixelTolerance && Math.abs(pointer - before) <= grab)) return;
        var base = axis === "x" ? area.x : area.y;
        var length = axis === "x" ? area.width : area.height;
        moves.push({ axis: axis, from: (before - offset - base) / length, to: (after - offset - base) / length });
    }
    add("x", old.x, now.x, grabbed.x, inset.left);
    add("x", maxX(old), maxX(now), grabbed.x, inset.right);
    add("y", old.y, now.y, grabbed.y, inset.top);
    add("y", maxY(old), maxY(now), grabbed.y, inset.bottom);
    return moves;
}

function target(frame, content, area, options) {
    var filling = options.fit === "fill" || (options.fit !== "free" && options.filled);
    var arriving = options.fit === "arrive" && !contains(content, center(frame));
    var wanted = filling ? content : options.fit === "free" ? frame : options.preferred || frame;
    var width = Math.max(Math.min(wanted.width, content.width, options.maximum.width), options.minimum.width);
    var height = Math.max(Math.min(wanted.height, content.height, options.maximum.height), options.minimum.height);
    var start = filling ? rect(content.x, content.y, width, height) : rect(frame.x, frame.y, width, height);
    return options.fit === "free" && !options.snap ? contain(start, content, area, options.side, options.walls) : arrive(start, content, area, arriving, options.side);
}

function pressPoint(old, now, pointer) {
    var dx = Math.abs(now.x - old.x) > pixelTolerance ? now.x - old.x : maxX(now) - maxX(old);
    var dy = Math.abs(now.y - old.y) > pixelTolerance ? now.y - old.y : maxY(now) - maxY(old);
    return { x: pointer.x - dx, y: pointer.y - dy };
}
