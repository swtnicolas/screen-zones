import { after, before } from "node:test";
import { execFileSync, spawn } from "node:child_process";
import { cpSync, existsSync, mkdirSync, mkdtempSync, openSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const repo = new URL("../..", import.meta.url).pathname;
const drive = join(repo, "build/drive");
const root = mkdtempSync(join(tmpdir(), "screenzones-e2e-"));
const socket = `sz-e2e-${process.pid}`;
const log = join(root, "kwin.log");
export const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const clients = [];
let kwin;
let bus;
let xdisplay = "";
let probes = 0;
let loads = 0;

function ini(values) {
    const quote = (text) => `"${text.replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`;
    return "[General]\n" + Object.entries(values).map(([key, value]) => `${key}=${typeof value === "string" ? quote(value) : value}`).join("\n") + "\n";
}

export function env(extra) {
    const vars = { ...process.env, XDG_CONFIG_HOME: join(root, "config"), XDG_DATA_HOME: join(root, "data"), XDG_CACHE_HOME: join(root, "cache") };
    delete vars.WAYLAND_DISPLAY;
    delete vars.WAYLAND_SOCKET;
    delete vars.DISPLAY;
    if (bus) vars.DBUS_SESSION_BUS_ADDRESS = bus;
    return { ...vars, ...extra };
}

export function qdbus(...args) {
    return execFileSync("qdbus6", ["org.kde.KWin", ...args], { env: env(), encoding: "utf8" }).trim();
}

export async function until(check, what, timeout = 5000) {
    const end = Date.now() + timeout;
    for (;;) {
        const value = await check();
        if (value) return value;
        if (Date.now() > end) throw new Error(`timed out waiting for ${what}`);
        await sleep(100);
    }
}

export async function load() {
    const target = join(root, `package-${++loads}`);
    cpSync(join(repo, "package"), target, { recursive: true });
    qdbus("/Scripting", "org.kde.kwin.Scripting.loadDeclarativeScript", join(target, "contents/ui/main.qml"), "local.screenzones");
    qdbus("/Scripting", "org.kde.kwin.Scripting.start");
    await sleep(500);
}

function completeLines() {
    const text = readFileSync(log, "utf8");
    return text.slice(0, text.lastIndexOf("\n") + 1).split("\n");
}

async function probe(prefix, expression) {
    const marker = `${prefix}${++probes}`;
    const file = join(root, `${marker}.js`);
    writeFileSync(file, `print("${marker} " + JSON.stringify(${expression}));`);
    qdbus("/Scripting", "org.kde.kwin.Scripting.loadScript", file, marker);
    qdbus("/Scripting", "org.kde.kwin.Scripting.start");
    const line = await until(() => completeLines().find((l) => l.includes(`${marker} `)), marker);
    qdbus("/Scripting", "org.kde.kwin.Scripting.unloadScript", marker);
    return JSON.parse(line.slice(line.indexOf(`${marker} `) + marker.length + 1));
}

export function windows() {
    return probe("SZE2E", `workspace.stackingOrder.map(function (w) {
        var g = w.frameGeometry;
        return { caption: w.caption, app: w.resourceClass, internal: w.pid === -1, popup: w.popupWindow, opacity: w.opacity, x: g.x, y: g.y, width: g.width, height: g.height, maximized: w.maximizeMode };
    })`);
}

export function run(source) {
    const marker = `SZRUN${++probes}`;
    const file = join(root, `${marker}.js`);
    writeFileSync(file, source);
    qdbus("/Scripting", "org.kde.kwin.Scripting.loadScript", file, marker);
    qdbus("/Scripting", "org.kde.kwin.Scripting.start");
    qdbus("/Scripting", "org.kde.kwin.Scripting.unloadScript", marker);
}

export function printed(title) {
    const file = join(root, `${title}.err`);
    return existsSync(file) ? readFileSync(file, "utf8") : "";
}

export async function frame(caption) {
    return (await windows()).find((w) => w.caption === caption && !w.internal);
}

export async function bars() {
    return (await windows()).filter((w) => w.internal && w.caption.startsWith("ScreenZones bar") && w.opacity > 0)
        .map(({ x, y, width, height }) => ({ x, y, width, height }))
        .sort((a, b) => a.x - b.x || a.y - b.y);
}

export function input(...commands) {
    return new Promise((resolve, reject) => {
        const child = spawn(drive, commands.map(String), { env: env(), stdio: ["ignore", "inherit", "inherit"] });
        child.on("exit", (code) => (code === 0 ? resolve() : reject(new Error(`drive exited ${code}`))));
    });
}

async function launch(title, args, platform) {
    const child = spawn("qml6", [join(repo, "tests/e2e/client.qml"), "--", title, ...args].map(String), {
        env: env({ ...platform, QT_FORCE_STDERR_LOGGING: "1" }), stdio: ["ignore", openSync(join(root, `${title}.log`), "w"), "pipe"]
    });
    child.stderr.on("data", (d) => writeFileSync(join(root, `${title}.err`), d, { flag: "a" }));
    clients.push(child);
    await until(() => frame(title), `window ${title}`);
    await sleep(400);
    return frame(title);
}

export function open(title, width, height, minimumWidth = 0, domain = "", minimumHeight = 0, closesWhenInactive = false) {
    return launch(title, [width, height, minimumWidth, minimumHeight, domain, closesWhenInactive ? "closes" : ""], { WAYLAND_DISPLAY: socket, QT_QPA_PLATFORM: "wayland" });
}

export function clickTray() {
    execFileSync("qdbus6", ["org.kde.kglobalaccel", "/component/kwin", "org.kde.kglobalaccel.Component.invokeShortcut", "ScreenZones Menu"], { env: env() });
}

export async function menuOpen() {
    return (await windows()).some((w) => w.internal && w.popup);
}

export function openX11(title, width, height) {
    return launch(title, [width, height], { DISPLAY: xdisplay, QT_QPA_PLATFORM: "xcb" });
}

export async function settled(caption) {
    let last = null;
    return until(async () => {
        const now = await frame(caption);
        const same = last && JSON.stringify(last) === JSON.stringify(now);
        last = now;
        return same ? now : null;
    }, `${caption} to settle`);
}

export const titleBar = (w) => [w.x + w.width / 2, w.y + 12];
export const inside = (w, r) => w.x >= r.x && w.y >= r.y && w.x + w.width <= r.x + r.width && w.y + w.height <= r.y + r.height;

export function screens() {
    return probe("SZSCREENS", `workspace.screens.map(function (o) {
        var g = o.geometry;
        var a = workspace.clientArea(KWin.MaximizeArea, o, workspace.currentDesktop);
        return { name: o.name, x: g.x, y: g.y, width: g.width, height: g.height, area: { x: a.x, y: a.y, width: a.width, height: a.height } };
    })`);
}

export function configure(...settings) {
    execFileSync("kscreen-doctor", settings, { env: env({ WAYLAND_DISPLAY: socket }), stdio: "ignore" });
}

function stop(child) {
    if (child.exitCode !== null || child.signalCode !== null) return Promise.resolve();
    const closed = new Promise((resolve) => child.once("close", resolve));
    child.kill();
    return closed;
}

async function stopGroup(group) {
    const alive = () => {
        try {
            process.kill(-group, 0);
            return true;
        } catch {
            return false;
        }
    };
    if (!alive()) return;
    process.kill(-group, "SIGTERM");
    try {
        await until(() => !alive(), "kwin to exit", 10000);
    } catch {
        if (alive()) process.kill(-group, "SIGKILL");
        await until(() => !alive(), "kwin to be killed");
    }
}

export function session(settings, { xwayland = false } = {}) {
    before(async () => {
        if (!existsSync(drive)) execFileSync("bash", [join(repo, "scripts/build-drive.sh")], { stdio: "inherit" });
        mkdirSync(join(root, "config"), { recursive: true });
        writeFileSync(join(root, "config/screenzonesrc"), ini(settings));
        const out = openSync(log, "w");
        const xsockets = new Set(readdirSync("/tmp/.X11-unix"));
        writeFileSync(join(root, "bus.conf"), `<busconfig>
  <type>session</type>
  <listen>unix:dir=${root}</listen>
  <auth>EXTERNAL</auth>
  <policy context="default"><allow send_destination="*" eavesdrop="true"/><allow eavesdrop="true"/><allow own="*"/></policy>
</busconfig>
`);
        kwin = spawn("dbus-run-session", [`--config-file=${join(root, "bus.conf")}`, "--", "bash", "-c",
            `echo "$DBUS_SESSION_BUS_ADDRESS" > ${root}/bus; exec kwin_wayland${xwayland ? " --xwayland" : ""} --virtual --width 1920 --height 1080 --output-count 2 --socket ${socket} --no-lockscreen`
        ], { env: env({ QT_FORCE_STDERR_LOGGING: "1" }), stdio: ["ignore", out, out], detached: true });
        bus = await until(() => existsSync(join(root, "bus")) && readFileSync(join(root, "bus"), "utf8").trim(), "session bus");
        await until(() => existsSync(join(process.env.XDG_RUNTIME_DIR, socket)), "wayland socket");
        await until(() => { try { return qdbus("/KWin", "org.kde.KWin.currentDesktop") !== ""; } catch { return false; } }, "kwin");
        if (xwayland) xdisplay = ":" + (await until(() => readdirSync("/tmp/.X11-unix").find((s) => !xsockets.has(s)), "xwayland socket")).slice(1);
        await load();
    });

    after(async () => {
        await Promise.all(clients.map(stop));
        if (kwin) await stopGroup(kwin.pid);
        if (!process.env.KEEP) rmSync(root, { recursive: true, force: true });
    });
}
