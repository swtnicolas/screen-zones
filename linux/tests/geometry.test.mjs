import { test } from "node:test";
import assert from "node:assert/strict";
import { load } from "./load.mjs";

const G = load("geometry");
const plain = (value) => JSON.parse(JSON.stringify(value));
const same = (actual, expected) => assert.deepEqual(plain(actual), expected);
const zone = (id, x, y, w, h) => ({ id, x, y, w, h });
const rect = (x, y, width, height) => ({ x, y, width, height });

const three = [zone("A", 0, 0, 0.5, 1), zone("B", 0.5, 0, 0.5, 0.5), zone("C", 0.5, 0.5, 0.5, 0.5)];
const two = [zone("A", 0, 0, 0.5, 1), zone("B", 0.5, 0, 0.5, 1)];
const rows = [zone("A", 0, 0, 1, 0.5), zone("B", 0, 0.5, 1, 0.5)];
const area = rect(3272, -81, 1920, 1080);
const display = rect(0, 0, 1920, 1080);
const desk = rect(0, 24, 1920, 1056);
const flat = { left: 0, top: 0, right: 0, bottom: 0 };

function matches(actual, expected) {
    assert.ok(actual, "expected zones, got null");
    assert.equal(actual.length, expected.length);
    actual.forEach((a, i) => {
        const e = expected[i];
        assert.equal(a.id, e.id);
        for (const key of ["x", "y", "w", "h"]) assert.ok(Math.abs(a[key] - e[key]) < 1e-9, `${a.id}.${key} ${a[key]} != ${e[key]}`);
    });
}

test("moving the vertical divider resizes every zone that touches it", () => {
    matches(G.moving(three, { axis: "x", from: 0.5, to: 0.6 }), [
        zone("A", 0, 0, 0.6, 1), zone("B", 0.6, 0, 0.4, 0.5), zone("C", 0.6, 0.5, 0.4, 0.5),
    ]);
});

test("moving the horizontal divider leaves the full-height zone alone", () => {
    matches(G.moving(three, { axis: "y", from: 0.5, to: 0.3 }), [
        zone("A", 0, 0, 0.5, 1), zone("B", 0.5, 0, 0.5, 0.3), zone("C", 0.5, 0.3, 0.5, 0.7),
    ]);
});

test("screen edges never move", () => {
    assert.equal(G.moving(three, { axis: "x", from: 0, to: 0.1 }), null);
    assert.equal(G.moving(three, { axis: "y", from: 1, to: 0.9 }), null);
});

test("a move that shrinks a zone below the minimum is rejected", () => {
    assert.equal(G.moving(three, { axis: "x", from: 0.5, to: 0.95 }), null);
});

test("a move on a line no zone has is rejected", () => {
    assert.equal(G.moving(three, { axis: "x", from: 0.3, to: 0.4 }), null);
});

test("a missing zone resolves to the nearest earlier letter", () => {
    const placed = two.map((z) => G.place(z, area, "top", 24));
    assert.equal(G.resolve(placed, "C").id, "B");
    assert.equal(G.resolve(placed, "A").id, "A");
});

test("placed zones share edges and reserve the bar", () => {
    const placed = three.map((z) => G.place(z, area, "top", 24));
    same(placed[0].full, rect(3272, -81, 960, 1080));
    same(placed[0].bar, rect(3272, -81, 960, 24));
    same(placed[0].content, rect(3272, -57, 960, 1056));
    same(placed[1].full, rect(4232, -81, 960, 540));
    same(placed[2].full, rect(4232, 459, 960, 540));
    same(placed[2].bar, rect(4232, 459, 960, 24));
    same(placed[2].content, rect(4232, 483, 960, 516));
    assert.equal(G.zoneAt(placed, { x: 4232, y: 459 }).id, "C");
    assert.equal(G.zoneAt(placed, { x: 4231, y: 459 }).id, "A");
});

test("a bar on each side takes its strip of the zone and leaves the rest to the windows", () => {
    const a = zone("A", 0, 0, 0.5, 1);
    const bottom = G.place(a, area, "bottom", 24);
    same([bottom.bar, bottom.content], [rect(3272, 975, 960, 24), rect(3272, -81, 960, 1056)]);
    const left = G.place(a, area, "left", 170);
    same([left.bar, left.content], [rect(3272, -81, 170, 1080), rect(3442, -81, 790, 1080)]);
    const right = G.place(a, area, "right", 170);
    same([right.bar, right.content], [rect(4062, -81, 170, 1080), rect(3272, -81, 790, 1080)]);
});

test("an opened side bar grows from its zone's edge, never wider than the zone", () => {
    same(G.widened(G.place(zone("A", 0, 0, 0.5, 1), area, "right", 30), "right", 170), rect(4062, -81, 170, 1080));
    same(G.widened(G.place(zone("A", 0, 0, 0.05, 1), area, "left", 30), "left", 170), rect(3272, -81, 96, 1080));
});

test("a window never slides under a side bar and an oversized one overflows away from it", () => {
    const left = G.place(zone("A", 0, 0, 0.5, 1), display, "left", 170).content;
    same(G.contain(rect(-300, 100, 400, 300), left, display), rect(170, 100, 400, 300));
    const right = G.place(zone("A", 0, 0, 0.5, 1), display, "right", 170).content;
    same(G.arrive(rect(0, 100, 1200, 300), right, display, false), rect(-410, 100, 1200, 300));
});

test("a window taller or wider than its content rect overflows away from its bar, past the display top when it must", () => {
    const below = G.place(zone("B", 0, 0.5, 1, 0.5), display, "bottom", 22);
    same(G.arrive(rect(0, 600, 400, 700), below.content, display, false, "bottom"), rect(0, 358, 400, 700));
    same(G.contain(rect(0, 600, 400, 700), below.content, display, "bottom"), rect(0, 358, 400, 700));
    same(G.arrive(rect(0, 600, 400, 1200), below.content, display, false, "bottom"), rect(0, -142, 400, 1200));
    const above = G.place(zone("A", 0, 0, 1, 0.5), display, "bottom", 22);
    same(G.arrive(rect(0, 0, 400, 700), above.content, display, false, "bottom"), rect(0, -182, 400, 700));
    same(G.contain(rect(0, 100, 400, 700), above.content, display, "bottom"), rect(0, -182, 400, 700));
    const middle = G.place(zone("B", 1 / 3, 0, 1 / 3, 1), display, "right", 170);
    same(G.arrive(rect(700, 100, 600, 300), middle.content, display, false, "right"), rect(510, 100, 600, 300));
    same(G.contain(rect(700, 100, 600, 300), middle.content, display, "right"), rect(510, 100, 600, 300));
});

test("divider lines skip the stretches under the bars", () => {
    const lines = (side, size) => {
        const placed = three.map((z) => G.place(z, area, side, size));
        return G.uncovered(G.dividers(placed, area, 1), placed.map((p) => p.bar));
    };
    same(lines("top", 24), [rect(4232, -57, 1, 516), rect(4232, 483, 1, 516)]);
    same(lines("left", 30), [rect(4262, 459, 930, 1)]);
});

test("a window covers a bar only when it overlaps it by more than the pixel tolerance on both axes", () => {
    const bar = rect(0, 292, 768, 22);
    assert.equal(G.covers(rect(0, 22, 480, 270.2857), bar), false);
    assert.equal(G.covers(rect(766, 100, 400, 400), bar), false);
    assert.equal(G.covers(rect(0, 22, 480, 273), bar), true);
    assert.equal(G.covers(rect(765, 100, 400, 400), bar), true);
});

test("a side bar keeps the longest stretch no window covers", () => {
    const bar = rect(455, 0, 30, 1040);
    same(G.visiblePart(bar, [], true), bar);
    same(G.visiblePart(bar, [rect(455, 854, 296, 186)], true), rect(455, 0, 30, 854));
    same(G.visiblePart(bar, [rect(400, -10, 300, 210.4)], true), rect(455, 201, 30, 839));
    same(G.visiblePart(bar, [rect(455, 300, 296, 100)], true), rect(455, 400, 30, 640));
    same(G.visiblePart(bar, [rect(455, 100, 296, 100), rect(455, 700, 296, 100)], true), rect(455, 200, 30, 500));
});

test("a top bar keeps the longest stretch along its width", () => {
    same(G.visiblePart(rect(0, 0, 960, 22), [rect(424, -2, 1152, 1058)], false), rect(0, 0, 424, 22));
});

test("a bar covered all along, or but for less than its thickness, has no visible part", () => {
    const bar = rect(455, 0, 30, 1040);
    assert.equal(G.visiblePart(bar, [rect(0, 0, 2000, 2000)], true), null);
    assert.equal(G.visiblePart(bar, [rect(455, 20, 296, 1020)], true), null);
});

test("a window overlapping a bar by no more than the pixel tolerance leaves it whole", () => {
    const bar = rect(455, 0, 30, 1040);
    same(G.visiblePart(bar, [rect(483, 0, 1336, 1040)], true), bar);
});

test("gesture tells moves from resizes and ignores jitter", () => {
    const old = rect(100, 100, 500, 400);
    assert.equal(G.gesture(old, rect(102, 99, 501, 400)), "unchanged");
    assert.equal(G.gesture(old, rect(300, 250, 500, 400)), "moved");
    assert.equal(G.gesture(old, rect(100, 100, 620, 400)), "resized");
});

test("dragging a window edge on a divider moves that divider", () => {
    const moves = G.edgeMoves(rect(3272, -57, 960, 1056), rect(3272, -57, 1152, 1056), { x: 4234, y: 300 }, area, flat);
    same(moves, [{ axis: "x", from: 0.5, to: 0.6 }]);
});

test("a top edge move counts the bar above the window", () => {
    const moves = G.edgeMoves(rect(4232, 483, 960, 516), rect(4232, 375, 960, 624), { x: 4600, y: 481 }, area, { ...flat, top: 24 });
    same(moves, [{ axis: "y", from: 0.5, to: 0.4 }]);
});

test("a right edge move counts the bar beside the window", () => {
    const moves = G.edgeMoves(rect(3272, -81, 790, 1080), rect(3272, -81, 982, 1080), { x: 4063, y: 300 }, area, { ...flat, right: -170 });
    same(moves, [{ axis: "x", from: 0.5, to: 0.6 }]);
});

test("an edge that moved away from the pointer is not a divider drag", () => {
    const moves = G.edgeMoves(rect(3272, -57, 960, 1056), rect(3272, -57, 1152, 1056), { x: 3700, y: 300 }, area, flat);
    same(moves, []);
});

test("a window inside its zone keeps its place and one arriving is centered", () => {
    const z = rect(1000, 0, 960, 540);
    same(G.arrive(rect(1100, 50, 400, 300), z, display), rect(1100, 50, 400, 300));
    same(G.arrive(rect(1700, 300, 400, 300), z, display), rect(1560, 240, 400, 300));
    same(G.arrive(rect(0, 0, 400, 300), z, display), rect(1280, 120, 400, 300));
    same(G.arrive(rect(-1500, 600, 2000, 300), z, display), rect(1000, 120, 2000, 300));
});

test("dividers draw each inner line once inside the zone after it and skip the display edges", () => {
    same(G.dividers(three.map((z) => G.place(z, area, "top", 24)), area, 1), [rect(4232, -81, 1, 1080), rect(4232, 459, 960, 1)]);
    same(G.dividers(two.map((z) => G.place(z, area, "top", 24)), area, 1), [rect(4232, -81, 1, 1080)]);
});

test("a free window stops at a divider instead of crossing into the neighbor zone", () => {
    same(G.contain(rect(800, 100, 400, 300), rect(0, 24, 960, 1056), desk), rect(560, 100, 400, 300));
    same(G.contain(rect(100, 400, 400, 300), rect(640, 24, 640, 516), desk), rect(640, 240, 400, 300));
});

test("a free window hangs past the display edge while a part stays inside", () => {
    const left = rect(0, 24, 960, 1056);
    same(G.contain(rect(-300, 900, 400, 300), left, desk), rect(-300, 900, 400, 300));
    same(G.contain(rect(-500, 1050, 400, 300), left, desk), rect(-320, 1000, 400, 300));
    same(G.contain(rect(-500, -50, 50, 40), left, desk), rect(0, 24, 50, 40));
});

const upper = rect(455, 0, 1920, 1080);
const lowerDisplay = rect(0, 1080, 2954, 1662);
const rightDisplay = rect(2375, 0, 1920, 1080);
const upperArea = rect(455, 0, 1920, 1040);

test("a display edge is a wall along a zone only where another display borders it", () => {
    same(G.walls(rect(485, 0, 1336, 1040), upper, [lowerDisplay, rightDisplay]), { left: false, right: true, bottom: true });
    same(G.walls(rect(485, 0, 1336, 1040), upper, [rect(-1465, 0, 1920, 1080), rightDisplay]), { left: true, right: true, bottom: false });
    same(G.walls(rect(1851, 0, 524, 1040), upper, [rect(0, 1080, 1800, 1000)]), { left: false, right: false, bottom: false });
    same(G.walls(rect(485, 0, 1336, 1040), upper, [rect(0, 1100, 2954, 1662), rect(2400, 0, 1920, 1080)]), { left: false, right: false, bottom: false });
});

test("a free window stops at a display edge that borders another display instead of hanging into it", () => {
    const left = rect(485, 0, 1336, 1040);
    const right = rect(1851, 0, 524, 1040);
    same(G.contain(rect(485, 424, 1336, 1040), left, upperArea, "left", { left: false, right: true, bottom: true }), rect(485, 0, 1336, 1040));
    same(G.contain(rect(2200, 100, 400, 300), right, upperArea, "left", { left: false, right: true, bottom: true }), rect(1975, 100, 400, 300));
    same(G.contain(rect(300, 100, 400, 300), rect(455, 22, 1366, 1018), upperArea, "top", { left: true, right: false, bottom: false }), rect(455, 100, 400, 300));
});

test("a window wider than its zone overflows only past the display edge when it has one", () => {
    same(G.contain(rect(700, 100, 1200, 300), rect(960, 24, 960, 1056), desk), rect(960, 100, 1200, 300));
    same(G.contain(rect(300, -50, 900, 700), rect(640, 24, 640, 516), desk), rect(380, 24, 900, 700));
});

test("placing without centering clamps a window that fits and sends an oversized one to the display edge", () => {
    const left = rect(0, 24, 960, 1056);
    same(G.arrive(rect(900, 100, 400, 300), left, display, false), rect(560, 100, 400, 300));
    same(G.arrive(rect(0, 100, 1200, 800), left, display, false), rect(-240, 100, 1200, 800));
});

test("an oversized window arrives overflowing past the display edge of its zone", () => {
    const left = rect(0, 24, 960, 1056);
    same(G.arrive(rect(1200, 100, 1200, 800), left, display), rect(-240, 152, 1200, 800));
    same(G.arrive(rect(100, 100, 1200, 800), left, display), rect(-240, 100, 1200, 800));
});

test("centering puts a fitting axis in the middle and an oversized one past the display edge", () => {
    const left = rect(0, 24, 960, 1056);
    same(G.centered(rect(700, 900, 400, 300), left, display), rect(280, 402, 400, 300));
    same(G.centered(rect(700, 900, 1200, 800), left, display), rect(-240, 152, 1200, 800));
});

test("compact tabs shrink every inactive tab to its icon and give the rest to the active one", () => {
    same(G.tabWidths([false, true, false], true, 400, 30, 240), [30, 240, 30]);
    same(G.tabWidths([false, true, false], true, 200, 30, 240), [30, 140, 30]);
    same(G.tabWidths([false, true, false], false, 400, 30, 240), [133, 133, 133]);
});

test("splitting halves a zone and letters zones in reading order", () => {
    matches(G.splitting(two, 1, "y"), three);
    matches(G.splitting([zone("A", 0, 0, 1, 1)], 0, "x"), two);
});

test("splits below the minimum size or above the zone limit are rejected", () => {
    assert.equal(G.splitting([zone("A", 0, 0, 0.15, 1)], 0, "x"), null);
    const nine = Array.from({ length: 9 }, (_, i) => zone(String.fromCharCode(65 + i), i / 9, 0, 1 / 9, 1));
    assert.equal(G.splitting(nine, 0, "y"), null);
});

test("editing a layout keeps each zone's bar side and both halves of a split inherit it", () => {
    const sided = [zone("A", 0, 0, 0.5, 1), { ...zone("B", 0.5, 0, 0.5, 1), tabsAt: "left" }];
    assert.deepEqual(G.splitting(sided, 1, "y").map((z) => z.tabsAt), [undefined, "left", "left"]);
    assert.deepEqual(G.moving(sided, { axis: "x", from: 0.5, to: 0.6 }).map((z) => z.tabsAt), [undefined, "left"]);
    const corner = [zone("A", 0, 0, 0.5, 0.5), sided[1], { ...zone("C", 0, 0.5, 0.5, 0.5), tabsAt: "right" }];
    assert.deepEqual(G.removing(corner, 0).map((z) => [z.id, z.tabsAt]), [["A", "right"], ["B", "left"]]);
});

test("removing a zone gives its space to the neighbors along a whole side", () => {
    matches(G.removing(three, 0), rows);
    matches(G.removing(three, 1), two);
});

test("the last zone cannot be removed", () => {
    assert.equal(G.removing([zone("A", 0, 0, 1, 1)], 0), null);
});

const zoneContent = rect(960, 24, 960, 1056);
const any = { width: 0, height: 0 };
const none = { width: 1e9, height: 1e9 };
const placing = (frame, options) => plain(G.target(frame, zoneContent, desk, { minimum: any, maximum: none, snap: false, filled: false, preferred: null, ...options }));

test("a window shrunk by a smaller zone grows back to its preferred size in a larger one", () => {
    assert.deepEqual(placing(rect(1000, 100, 500, 400), { fit: "keep", preferred: { width: 1200, height: 700 } }), rect(960, 100, 960, 700));
    assert.deepEqual(placing(rect(1000, 100, 500, 400), { fit: "keep", preferred: { width: 800, height: 700 } }), rect(1000, 100, 800, 700));
});

test("a window that filled its zone fills it again and a free move never refills it", () => {
    assert.deepEqual(placing(rect(1000, 100, 500, 400), { fit: "keep", filled: true }), zoneContent);
    assert.deepEqual(placing(rect(1000, 100, 500, 400), { fit: "free", filled: true }), rect(1000, 100, 500, 400));
});

test("a window arriving from elsewhere is centered and one inside keeps its place", () => {
    assert.deepEqual(placing(rect(100, 100, 400, 300), { fit: "arrive" }), rect(1240, 402, 400, 300));
    assert.deepEqual(placing(rect(1000, 100, 400, 300), { fit: "arrive" }), rect(1000, 100, 400, 300));
});

test("a free resize stays contained in the zone and the magnet clamps it inside", () => {
    assert.deepEqual(placing(rect(1800, 100, 400, 300), { fit: "free" }), rect(1800, 100, 400, 300));
    assert.deepEqual(placing(rect(1800, 100, 400, 300), { fit: "free", snap: true }), rect(1520, 100, 400, 300));
    assert.deepEqual(placing(rect(700, 100, 400, 300), { fit: "free" }), rect(960, 100, 400, 300));
});

test("the window's minimum size wins over the zone and its maximum over filling", () => {
    assert.deepEqual(placing(rect(1000, 100, 500, 400), { fit: "fill", minimum: { width: 1100, height: 0 } }), rect(960, 24, 1100, 1056));
    assert.deepEqual(placing(rect(1000, 100, 500, 400), { fit: "fill", maximum: { width: 800, height: 600 } }), rect(960, 24, 800, 600));
});

test("the grabbed point of a resize sits where the moved edges started, whatever the pointer drifted", () => {
    const old = rect(0, 22, 960, 1058);
    assert.deepEqual(plain(G.pressPoint(old, rect(0, 22, 1108, 1058), { x: 1110, y: 500 })), { x: 962, y: 500 });
    assert.deepEqual(plain(G.pressPoint(rect(960, 22, 960, 1058), rect(800, 22, 1120, 1058), { x: 798, y: 300 })), { x: 958, y: 300 });
    assert.deepEqual(plain(G.pressPoint(old, rect(0, 22, 960, 900), { x: 400, y: 925 })), { x: 400, y: 1083 });
});
