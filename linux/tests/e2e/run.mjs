import { test } from "node:test";
import assert from "node:assert/strict";
import { bars, frame, input, inside, load, open, printed, qdbus, run, session, settled, sleep, titleBar, windows } from "./harness.mjs";

const zonesA = [{ id: "A", x: 0, y: 0, w: 0.5, h: 1 }, { id: "B", x: 0.5, y: 0, w: 0.5, h: 1 }];

session({
    displays: JSON.stringify({ "Virtual-0": { name: "Virtual-0", layout: "Dos" }, "Virtual-1": { name: "Virtual-1" } }),
    layouts: JSON.stringify([{ name: "Dos", zones: zonesA }]),
    lockZones: false
});
const contentA = { x: 0, y: 22, width: 960, height: 1058 };
let divider = 960;
const zoneB = () => ({ x: divider, y: 22, width: 1920 - divider, height: 1058 });
const contentB = { x: 960, y: 22, width: 960, height: 1058 };

test("every zone of every enabled display gets a bar across its top", async () => {
    await open("one", 400, 300);
    assert.deepEqual(await bars(), [
        { x: 0, y: 0, width: 960, height: 22 },
        { x: 960, y: 0, width: 960, height: 22 },
        { x: 1920, y: 0, width: 1920, height: 22 },
    ]);
});

test("a new window without rule or memory lands in zone A of the display under it", async () => {
    const one = await settled("one");
    assert.ok(inside(one, contentA), JSON.stringify(one));
});

test("a window dragged by its title bar into the neighbor zone stays inside its own zone", async () => {
    const one = await settled("one");
    await input("drag", ...titleBar(one), 1500, 500, 20);
    const after = await settled("one");
    assert.ok(inside(after, contentA), JSON.stringify(after));
    assert.equal(after.x + after.width, 960);
});

test("maximizing fills the zone instead of the screen and maximizing again restores the window, never sized to the screen on the way", async () => {
    const before = await settled("one");
    let seen = printed("one").length;
    await input("dclick", ...titleBar(before));
    const filled = await settled("one");
    assert.deepEqual({ x: filled.x, y: filled.y, width: filled.width, height: filled.height, maximized: filled.maximized }, { ...contentA, maximized: 0 });
    assert.deepEqual(printed("one").slice(seen).match(/width \d+/g), [`width ${contentA.width}`]);
    seen = printed("one").length;
    await input("dclick", ...titleBar(filled));
    const restored = await settled("one");
    assert.deepEqual([restored.x, restored.y, restored.width, restored.height], [before.x, before.y, before.width, before.height]);
    assert.deepEqual(printed("one").slice(seen).match(/width \d+/g), [`width ${before.width}`]);
});

test("a quick tile fills the zone instead and the window is never sized to the tile on the way", async () => {
    await settled("one");
    const seen = printed("one").length;
    run(`var w = workspace.stackingOrder.filter(function (w) { return w.caption === "one"; })[0]; workspace.activeWindow = w; workspace.slotWindowQuickTileTopLeft();`);
    await sleep(600);
    const filled = await settled("one");
    assert.deepEqual({ x: filled.x, y: filled.y, width: filled.width, height: filled.height }, contentA);
    assert.equal((printed("one").slice(seen).match(/height \d+/g) || []).length, 1);
    await input("dclick", ...titleBar(filled));
    await settled("one");
});

test("with the zone sizes unlocked, resizing a window that fills its zone by the edge on a divider moves that divider", async () => {
    const one = await settled("one");
    await input("dclick", ...titleBar(one));
    const filled = await settled("one");
    await input("drag", filled.x + filled.width + 1, 500, 1153, 500, 20);
    const resized = await settled("one");
    divider = resized.width;
    assert.ok(Math.abs(divider - 1152) <= 10, `divider at ${divider}`);
    assert.deepEqual((await bars()).slice(0, 2), [{ x: 0, y: 0, width: divider, height: 22 }, { x: divider, y: 0, width: 1920 - divider, height: 22 }]);
});

test("a bar hides only the stretch another window covers and shows whole again when it leaves", async () => {
    const one = await settled("one");
    const pressed = input("move", ...titleBar(one), "down", "move", 1000, 200, "move", 1000, 10, "wait", 1500, "up");
    await sleep(900);
    const dragged = await frame("one");
    const during = await bars();
    await pressed;
    await settled("one");
    await sleep(300);
    const left = Math.floor(dragged.x);
    const right = Math.ceil(dragged.x + dragged.width);
    assert.deepEqual(during, [
        { x: 0, y: 0, width: left, height: 22 },
        { x: right, y: 0, width: 1920 - right, height: 22 },
        { x: 1920, y: 0, width: 1920, height: 22 },
    ]);
    assert.deepEqual(await bars(), [
        { x: 0, y: 0, width: divider, height: 22 },
        { x: divider, y: 0, width: 1920 - divider, height: 22 },
        { x: 1920, y: 0, width: 1920, height: 22 },
    ]);
});

test("a tab dragged onto another zone moves its window into that zone", async () => {
    await input("drag", 60, 11, 1500, 500, 20);
    const moved = await settled("one");
    assert.ok(inside(moved, zoneB()), JSON.stringify(moved));
});

test("a new window opens in the last zone its app used on this set of displays", async () => {
    await open("two", 300, 200);
    const two = await settled("two");
    assert.ok(inside(two, zoneB()), JSON.stringify(two));
});

test("a window dragged past a display edge that borders another display stops at that edge", async () => {
    const [x, y] = titleBar(await settled("two"));
    await input("drag", x, y, 1900, y, 20);
    const two = await settled("two");
    assert.equal(two.x + two.width, 1920);
});

test("a window wider than its zone overflows past the display edge instead of covering the neighbor zone", async () => {
    await input("drag", divider + 30, 11, 400, 500, 20);
    await open("wide", 400, 300, 1300);
    const wide = await settled("wide");
    assert.equal(wide.x + wide.width, divider);
    assert.ok(wide.x < 0);
});

const box = ({ x, y, width, height }) => ({ x: Math.round(x), y: Math.round(y), width: Math.round(width), height: Math.round(height) });
const fullZoneB = () => ({ x: divider, y: 0, width: 1920 - divider, height: 1080 });
const fullScreen = (on) => run(`workspace.stackingOrder.filter(function (w) { return w.caption === "two"; })[0].fullScreen = ${on};`);
const toggleZoneFullScreen = () => input("move", 2200, 300, "rclick", 1930, 10, "wait", 500, "move", 2020, 273, "wait", 300, "click", 2020, 273, "wait", 600);
const widthsSince = (seen) => printed("two").slice(seen).match(/width \d+/g) || [];
let windowed;

test("a window in full screen fills its own zone from its first frame and hides only that zone's bar", async () => {
    windowed = box(await settled("two"));
    const seen = printed("two").length;
    fullScreen(true);
    await sleep(600);
    assert.deepEqual(box(await settled("two")), fullZoneB());
    assert.deepEqual(widthsSince(seen), [`width ${1920 - divider}`]);
    assert.deepEqual(await bars(), [{ x: 0, y: 0, width: divider, height: 22 }, { x: 1920, y: 0, width: 1920, height: 22 }]);
});

test("a window entering full screen again from the same frame is never sized to its display on the way", async () => {
    fullScreen(false);
    assert.deepEqual(box(await settled("two")), windowed);
    const seen = printed("two").length;
    fullScreen(true);
    await sleep(600);
    assert.deepEqual(box(await settled("two")), fullZoneB());
    assert.deepEqual(widthsSince(seen), [`width ${1920 - divider}`]);
});

test("turning full screen in the zone off from the menu gives the window its display and hides only that display's bars", async () => {
    await toggleZoneFullScreen();
    assert.deepEqual(box(await settled("two")), { x: 0, y: 0, width: 1920, height: 1080 });
    assert.deepEqual(await bars(), [{ x: 1920, y: 0, width: 1920, height: 22 }]);
});

test("turning full screen in the zone back on returns the window to its zone", async () => {
    await toggleZoneFullScreen();
    assert.deepEqual(box(await settled("two")), fullZoneB());
});

test("leaving full screen returns the window to its frame in the zone and shows every bar", async () => {
    fullScreen(false);
    await sleep(600);
    assert.deepEqual(box(await settled("two")), windowed);
    assert.equal((await bars()).length, 3);
});

test("reloading the script keeps every window where it was", async () => {
    const before = (await windows()).filter((w) => !w.internal);
    qdbus("/Scripting", "org.kde.kwin.Scripting.unloadScript", "local.screenzones");
    await sleep(300);
    assert.equal((await bars()).length, 0);
    await load();
    await sleep(600);
    const after = (await windows()).filter((w) => !w.internal);
    assert.deepEqual(after, before);
    assert.equal((await bars()).length, 3);
});

const choose = (row, item) => input("move", 300, 300, "rclick", 10, 10, "wait", 500, "move", 100, row, "wait", 600,
    "move", 300, row, "wait", 300, "click", 400, item, "wait", 600);

test("the menu turns zones off on a display and back on", async () => {
    await choose(120, 120);
    assert.deepEqual((await bars()).filter((b) => b.x >= 1920), []);
    await choose(120, 120);
    assert.deepEqual((await bars()).filter((b) => b.x >= 1920), [{ x: 1920, y: 0, width: 1920, height: 22 }]);
});

test("the editor splits a zone and saving it changes the display's layout", async () => {
    await input("move", 300, 300, "rclick", 10, 10, "wait", 500, "move", 100, 90, "wait", 600, "move", 300, 90, "wait", 300,
        "move", 400, 219, "wait", 600, "move", 600, 219, "wait", 300, "click", 650, 219, "wait", 600);
    const cell = divider - 8;
    await input("click", Math.round(4 + (cell - 148) / 2 + 22), 594, "wait", 300, "key", "enter", "wait", 600);
    const fraction = Math.round(divider / 1920 * 10000) / 10000;
    const half = Math.round(fraction / 2 * 10000) / 10000;
    assert.deepEqual((await bars()).map((b) => b.x), [0, Math.round(half * 1920), Math.round(fraction * 1920), 1920]);
});

test("a click on a zone letter shows the zone's sizes below its bar and a second click hides them", async () => {
    const badge = async () => (await windows()).find((w) => w.internal && w.caption.startsWith("ScreenZones badge"));
    await input("move", 300, 300, "click", 10, 10, "wait", 400);
    const shown = await badge();
    assert.ok(shown, "no badge");
    assert.equal(shown.y, 26);
    assert.ok(shown.width > 150 && shown.height > 50, JSON.stringify(shown));
    await input("move", 300, 300, "click", 10, 10, "wait", 400);
    assert.equal(await badge(), undefined);
});
