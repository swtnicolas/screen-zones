import { test } from "node:test";
import assert from "node:assert/strict";
import { bars, input, open, run, session, settled, sleep, titleBar } from "./harness.mjs";

const halves = [{ id: "A", x: 0, y: 0, w: 0.5, h: 1 }, { id: "B", x: 0.5, y: 0, w: 0.5, h: 1 }];

session({
    displays: JSON.stringify({ "Virtual-0": { name: "Virtual-0", layout: "Dos" }, "Virtual-1": { name: "Virtual-1", tabsAt: "top" } }),
    layouts: JSON.stringify([{ name: "Dos", zones: halves }]),
    tabsAt: "left",
    compactTabs: true
});
const box = ({ x, y, width, height }) => ({ x, y, width, height });

test("each display puts its bars on its own side, else on the general one", async () => {
    await open("one", 400, 300);
    assert.deepEqual(await bars(), [
        { x: 0, y: 0, width: 30, height: 1080 },
        { x: 960, y: 0, width: 30, height: 1080 },
        { x: 1920, y: 0, width: 1920, height: 22 },
    ]);
});

test("a window filling its zone stays clear of the side bar", async () => {
    await input("dclick", ...titleBar(await settled("one")));
    assert.deepEqual(box(await settled("one")), { x: 30, y: 0, width: 930, height: 1080 });
});

test("a compact side bar opens over the window while the pointer is on it and leaves the window in place", async () => {
    await input("move", 500, 500, "move", 15, 300, "wait", 600);
    assert.deepEqual((await bars())[0], { x: 0, y: 0, width: 170, height: 1080 });
    assert.deepEqual(box(await settled("one")), { x: 30, y: 0, width: 930, height: 1080 });
    await input("move", 500, 300);
    await sleep(800);
    assert.deepEqual((await bars())[0], { x: 0, y: 0, width: 30, height: 1080 });
});

test("a zone takes its own bar side from the menu of its letter and leaves the other zones alone", async () => {
    await input("move", 500, 300, "move", 15, 11, "wait", 400, "rclick", 15, 11, "wait", 500, "move", 100, 58, "wait", 600,
        "move", 350, 58, "wait", 300, "click", 400, 91, "wait", 800);
    assert.deepEqual(await bars(), [
        { x: 0, y: 0, width: 960, height: 22 },
        { x: 960, y: 0, width: 30, height: 1080 },
        { x: 1920, y: 0, width: 1920, height: 22 },
    ]);
    assert.deepEqual(box(await settled("one")), { x: 0, y: 22, width: 960, height: 1058 });
});

test("a tab's menu sets the bar side of the tab's zone", async () => {
    await input("move", 500, 300, "move", 100, 11, "rclick", 100, 11, "wait", 500, "move", 150, 151, "wait", 600,
        "move", 330, 151, "wait", 300, "click", 330, 212, "wait", 800);
    assert.deepEqual((await bars())[0], { x: 0, y: 1058, width: 960, height: 22 });
    assert.deepEqual(box(await settled("one")), { x: 0, y: 0, width: 960, height: 1058 });
});

test("a display's submenu sets the bar side of every zone of that display that has none of its own", async () => {
    await input("move", 500, 300, "move", 975, 11, "wait", 400, "rclick", 975, 11, "wait", 500, "move", 1050, 121, "wait", 600,
        "move", 1350, 121, "wait", 300, "move", 1350, 216, "wait", 600, "move", 1550, 216, "wait", 300, "click", 1550, 340, "wait", 800);
    assert.deepEqual((await bars()).filter((b) => b.x >= 1920), [{ x: 3810, y: 0, width: 30, height: 1080 }]);
});

test("a tab's menu frees its app from the zones", async () => {
    await input("move", 500, 300, "move", 100, 1069, "rclick", 100, 1069, "wait", 500, "move", 120, 1055, "wait", 300, "click", 120, 1055, "wait", 600);
    run(`workspace.stackingOrder.filter(function (w) { return w.caption === "one"; })[0].setMaximize(true, true);`);
    assert.deepEqual(box(await settled("one")), { x: 0, y: 0, width: 1920, height: 1080 });
});

test("a window taller than its zone overflows above the display and leaves its bottom bar uncovered", async () => {
    run(`workspace.stackingOrder.filter(function (w) { return w.caption === "one"; })[0].minimized = true;`);
    await open("tall", 400, 1070, 0, "tall.example", 1070);
    assert.deepEqual(box(await settled("tall")), { x: 280, y: -12, width: 400, height: 1070 });
    assert.deepEqual((await bars())[0], { x: 0, y: 1058, width: 960, height: 22 });
});
