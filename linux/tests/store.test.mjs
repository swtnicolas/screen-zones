import { test } from "node:test";
import assert from "node:assert/strict";
import { load } from "./load.mjs";

const S = load("store");
const plain = (value) => JSON.parse(JSON.stringify(value));
const zone = (id, x, y, w, h) => ({ id, x, y, w, h });
const halves = [zone("A", 0, 0, 0.5, 1), zone("B", 0.5, 0, 0.5, 1)];
const moved = [zone("A", 0, 0, 0.6, 1), zone("B", 0.6, 0, 0.4, 1)];
const thirds = [zone("A", 0, 0, 1 / 3, 1), zone("B", 1 / 3, 0, 2 / 3, 1)];

function withState() {
    const state = S.load({});
    const name = S.add(state, { name: "Dos", zones: halves });
    for (const key of ["one", "two"]) {
        S.enable(state, key);
        S.choose(state, key, name);
    }
    return { state, name };
}

const zonesOf = (state, key) => plain(S.zonesOf(state, key));

test("a moved divider changes only its display and leaves the layout as saved", () => {
    const { state, name } = withState();
    S.setDraft(state, "one", moved);
    assert.deepEqual(zonesOf(state, "one"), moved);
    assert.deepEqual(zonesOf(state, "two"), halves);
    assert.deepEqual(plain(S.layoutNamed(state, name).zones), halves);
});

test("unsaved zones survive a reload", () => {
    const { state } = withState();
    S.setDraft(state, "one", moved);
    const reloaded = S.load({ displays: JSON.stringify(state.displays), layouts: JSON.stringify(state.layouts) });
    assert.deepEqual(zonesOf(reloaded, "one"), moved);
});

test("a display saved without a layout shows one column", () => {
    const state = S.load({ displays: JSON.stringify({ one: {} }) });
    assert.deepEqual(zonesOf(state, "one"), plain(S.single.zones));
});

test("dividers moved back to the saved zones leave nothing unsaved", () => {
    const { state } = withState();
    S.setDraft(state, "one", moved);
    S.setDraft(state, "one", halves);
    assert.equal(S.hasDraft(state, "one"), false);
});

test("saving a layout clears the unsaved zones of every display showing it", () => {
    const { state, name } = withState();
    S.setDraft(state, "one", moved);
    S.setDraft(state, "two", moved);
    S.setZones(state, name, thirds);
    assert.deepEqual(zonesOf(state, "one"), thirds);
    assert.deepEqual(zonesOf(state, "two"), thirds);
});

test("choosing a layout discards the display's unsaved zones", () => {
    const { state, name } = withState();
    S.setDraft(state, "one", moved);
    S.choose(state, "one", name);
    assert.deepEqual(zonesOf(state, "one"), halves);
});

test("renaming a layout keeps every display that shows it", () => {
    const { state, name } = withState();
    S.add(state, { name: "Casa", zones: thirds });
    S.rename(state, name, "casa");
    assert.equal(state.displays.one.layout, "casa 2");
    assert.deepEqual(zonesOf(state, "two"), halves);
});

test("removing a layout sends its displays to one column without their unsaved zones", () => {
    const { state, name } = withState();
    S.setDraft(state, "one", moved);
    S.remove(state, name);
    assert.deepEqual(zonesOf(state, "one"), plain(S.single.zones));
});

test("a taken name gets the first free number ignoring case", () => {
    assert.equal(S.unique("Trabajo", ["trabajo", "Trabajo 2"]), "Trabajo 3");
    assert.equal(S.unique("una columna", []), "una columna 2");
    assert.equal(S.unique("Casa", ["Trabajo"]), "Casa");
});

const surfaces = [
    { key: "right", bounds: { x: 1920 }, placed: [{ id: "A" }, { id: "B" }, { id: "C" }] },
    { key: "left", bounds: { x: 0 }, placed: [{ id: "A" }, { id: "B" }] },
];

test("a rule without a display goes to the leftmost display that has its zone", () => {
    assert.deepEqual(plain(S.resolveRule({ zone: "B" }, surfaces)), { display: "left", zone: "B" });
    assert.deepEqual(plain(S.resolveRule({ zone: "C" }, surfaces)), { display: "right", zone: "C" });
});

test("a rule for a display without zones applies nowhere", () => {
    assert.equal(S.resolveRule({ display: "gone", zone: "A" }, surfaces), null);
});

test("each set of displays keeps its own last zone per app", () => {
    const state = S.load({});
    S.record(state, S.displaySet(["left", "right"]), "konsole", "right", "C");
    S.record(state, S.displaySet(["left"]), "konsole", "left", "A");
    assert.deepEqual(plain(state.last["left right"].konsole), { display: "right", zone: "C" });
});

test("giving a free app a rule puts it back in zones", () => {
    const state = S.load({});
    S.setFree(state, "kate");
    assert.equal(S.setRule(state, "kate", { zone: "B" }), true);
    assert.deepEqual(plain(state.free), []);
    assert.deepEqual(plain(state.rules.kate), { zone: "B" });
});

test("a display follows the general bar side until it picks its own", () => {
    const { state } = withState();
    assert.equal(S.sideOf(state, "one", "left"), "left");
    S.setSide(state, "one", "right");
    assert.equal(S.sideOf(state, "one", "left"), "right");
    assert.equal(S.sideOf(state, "two", "left"), "left");
    S.setSide(state, "one", null);
    assert.equal(S.sideOf(state, "one", "bottom"), "bottom");
});

test("a saved bar side survives loading and an unknown one falls back to the top", () => {
    const state = S.load({ displays: JSON.stringify({ one: { tabsAt: "bottom" }, two: { tabsAt: "diagonal" } }) });
    assert.equal(S.sideOf(state, "one", "left"), "bottom");
    assert.equal(S.sideOf(state, "two", "diagonal"), "top");
});

test("a zone's own bar side wins over its display's and travels with its layout", () => {
    const { state, name } = withState();
    S.setSide(state, "two", "bottom");
    S.setZoneSide(state, "one", "B", "left");
    const sides = (key) => S.zonesOf(state, key).map((z) => S.zoneSide(z, S.sideOf(state, key, "top")));
    assert.deepEqual(sides("one"), ["top", "left"]);
    assert.deepEqual(sides("two"), ["bottom", "left"]);
    S.setZoneSide(state, "one", "B", null);
    assert.deepEqual(plain(S.layoutNamed(state, name).zones), halves);
});

test("a zone's bar side reaches every unsaved draft of its layout", () => {
    const { state } = withState();
    S.setDraft(state, "one", moved);
    S.setDraft(state, "two", moved);
    S.setZoneSide(state, "two", "A", "right");
    assert.deepEqual(["one", "two"].map((key) => S.zonesOf(state, key)[0].tabsAt), ["right", "right"]);
});

test("the bar side of the only zone of Una columna is its display's", () => {
    const state = S.load({});
    S.enable(state, "one");
    S.setZoneSide(state, "one", "A", "right");
    assert.equal(S.sideOf(state, "one", "top"), "right");
    assert.deepEqual(plain(S.single.zones), [zone("A", 0, 0, 1, 1)]);
});
