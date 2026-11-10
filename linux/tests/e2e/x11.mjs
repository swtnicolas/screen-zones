import { test } from "node:test";
import assert from "node:assert/strict";
import { bars, input, openX11, printed, run, session, settled, sleep, titleBar } from "./harness.mjs";

session({
    displays: JSON.stringify({ "Virtual-0": { name: "Virtual-0", layout: "Dos" }, "Virtual-1": { name: "Virtual-1" } }),
    layouts: JSON.stringify([{ name: "Dos", zones: [{ id: "A", x: 0, y: 0, w: 0.5, h: 1 }, { id: "B", x: 0.5, y: 0, w: 0.5, h: 1 }] }])
}, { xwayland: true });
const box = ({ x, y, width, height }) => ({ x: Math.round(x), y: Math.round(y), width: Math.round(width), height: Math.round(height) });
const sizesSince = (seen) => printed("x11").slice(seen).match(/(width|height) \d+/g) || [];
const fullScreen = (on) => run(`workspace.stackingOrder.filter(function (w) { return w.caption === "x11"; })[0].fullScreen = ${on};`);

test("an X11 window entering full screen fills its zone and is never sized to its display on the way", async () => {
    await openX11("x11", 400, 300);
    const windowed = box(await settled("x11"));
    const seen = printed("x11").length;
    fullScreen(true);
    await sleep(600);
    assert.deepEqual(box(await settled("x11")), { x: 0, y: 0, width: 960, height: 1080 });
    assert.deepEqual(sizesSince(seen), ["width 960", "height 1080"]);
    fullScreen(false);
    await sleep(600);
    assert.deepEqual(box(await settled("x11")), windowed);
});

test("maximizing an X11 window fills its zone once", async () => {
    await input("dclick", ...titleBar(await settled("x11")));
    assert.deepEqual(box(await settled("x11")), { x: 0, y: 22, width: 960, height: 1058 });
});

test("with the zone sizes locked, resizing a window that fills its zone by the edge on a divider leaves the zones as they were", async () => {
    await input("drag", 961, 500, 1153, 500, 20);
    assert.deepEqual(box(await settled("x11")), { x: 0, y: 22, width: 960, height: 1058 });
    assert.deepEqual((await bars()).slice(0, 2), [{ x: 0, y: 0, width: 960, height: 22 }, { x: 960, y: 0, width: 960, height: 22 }]);
});
