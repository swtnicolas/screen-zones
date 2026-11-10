import { test } from "node:test";
import assert from "node:assert/strict";
import { bars, configure, input, open, printed, run, screens, session, settled, until } from "./harness.mjs";
import { load } from "../load.mjs";

const G = load("geometry");
const zones = [
    { id: "A", x: 0, y: 0, w: 0.4378, h: 0.4725 },
    { id: "B", x: 0.4378, y: 0, w: 0.2624, h: 0.4725 },
    { id: "C", x: 0.7002, y: 0, w: 0.2998, h: 1 },
    { id: "D", x: 0, y: 0.4725, w: 0.7002, h: 0.5275 },
];

session({
    displays: JSON.stringify({ "Virtual-0": { name: "Virtual-0", layout: "Cuatro" } }),
    layouts: JSON.stringify([{ name: "Cuatro", zones }]),
    free: JSON.stringify(["example.free.qml6"])
});

async function expected() {
    const display = (await screens()).find((s) => s.name === "Virtual-0");
    return zones.map((z) => JSON.parse(JSON.stringify(G.place(z, display.area, "top", 22).bar))).sort((a, b) => a.x - b.x || a.y - b.y);
}

const lower = (want) => want.find((b) => b.y > want[0].y);

async function barsOnZones() {
    const want = await expected();
    await until(async () => JSON.stringify(await bars()) === JSON.stringify(want), "bars on their zones", 8000).catch(() => {});
    assert.deepEqual(await bars(), want);
    return want;
}

test("a window that fills its zone at a fractional scale leaves the bar of the zone below it shown", async () => {
    await open("one", 600, 400);
    configure("output.Virtual-0.scale.1.75");
    const want = await barsOnZones();
    const one = await settled("one");
    const below = lower(want);
    assert.ok(one.y + one.height > below.y, JSON.stringify({ one, below }));
});

test("every bar follows its zone when the display's scale and position change", async () => {
    for (const settings of [["output.Virtual-0.scale.1.4"], ["output.Virtual-0.scale.2", "output.Virtual-0.position.200,1080"], ["output.Virtual-0.scale.1"]]) {
        configure(...settings);
        await barsOnZones();
    }
});

test("a click on the stretch of a bar another window covers reaches that window", async () => {
    const below = lower(await expected());
    await open("loose", 300, 200, 0, "free.example");
    run(`workspace.stackingOrder.filter(function (w) { return w.caption === "loose"; })[0].frameGeometry = { x: ${below.x + 50}, y: ${below.y - 40}, width: 300, height: 200 };`);
    await settled("loose");
    await until(async () => (await bars()).some((b) => b.y === below.y && b.x >= below.x + 350), "the covered stretch of the bar to hide");
    await input("move", below.x + 150, below.y + 11, "click", below.x + 150, below.y + 11, "wait", 300);
    assert.match(printed("loose"), /clicked/);
});
