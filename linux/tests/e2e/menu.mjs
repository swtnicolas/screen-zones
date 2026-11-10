import { test } from "node:test";
import assert from "node:assert/strict";
import { clickTray, frame, input, menuOpen, open, session, sleep, until } from "./harness.mjs";

session({ displays: JSON.stringify({ "Virtual-0": { name: "Virtual-0" } }) });

test("the tray menu stays open when the window it took focus from closes on losing it", async () => {
    await open("one", 400, 300);
    await open("launcher", 300, 300, 0, "", 0, true);
    clickTray();
    await until(async () => !(await frame("launcher")), "launcher to close");
    await sleep(1000);
    assert.ok(await menuOpen(), "menu closed");
    await input("move", 2900, 700, "click", 2900, 700, "wait", 300);
});

test("a menu item that activates a window closes the menu for good", async () => {
    await open("two", 400, 300);
    await input("move", 500, 500, "move", 100, 11, "rclick", 100, 11, "wait", 500, "move", 150, 58, "wait", 200, "click", 150, 58);
    await sleep(1200);
    assert.equal(await menuOpen(), false);
});
