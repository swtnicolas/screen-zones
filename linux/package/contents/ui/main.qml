import QtQuick
import QtCore
import Qt.labs.platform as P
import org.kde.kwin
import "../code/geometry.js" as Geometry
import "../code/store.js" as Store

Item {
    id: root

    readonly property int barHeight: 22
    readonly property int sideWidth: 170
    readonly property int narrowWidth: 30
    readonly property var sideNames: ({ top: "Arriba", bottom: "Abajo", left: "Izquierda", right: "Derecha" })
    readonly property int lineWidth: 1
    readonly property string defaultZone: "A"
    readonly property int pendingTime: 500
    readonly property int reopenWithin: 1000
    readonly property real restoreNudge: 1 / 256

    property var config: Store.load({})
    property var surfaces: ({})
    property var tracked: ({})
    property var saved: ({})
    property var bars: ({})
    property var lines: []
    property var maximizing: ({})
    property var changed: ({})
    property int counter: 0
    property int overlays: 0
    property real holdUntil: 0
    property var gesture: null
    property var lastGesture: null
    property var carry: null
    property string zoneInfo: ""
    property var editor: null
    property var badge: null
    property var ghost: null
    property string ghostKey: ""
    property bool paused: false
    property bool running: false
    property var menu: null
    property real menuOpened: 0
    property bool menuHidden: false
    property bool focusMoved: false

    Settings {
        id: settings
        location: StandardPaths.writableLocation(StandardPaths.ConfigLocation) + "/screenzonesrc"
        property string displays: "{}"
        property string layouts: "[]"
        property string rules: "{}"
        property string free: "[]"
        property string last: "{}"
        property string windows: "{}"
        property bool borders: true
        property bool compactTabs: false
        property string tabsAt: "top"
        property bool snap: false
        property bool lockZones: true
        property bool zoneFullScreen: true
    }

    function rectOf(r) {
        return Geometry.rect(r.x, r.y, r.width, r.height);
    }

    function pointOf(p) {
        return { x: p.x, y: p.y };
    }

    function idOf(w) {
        return w.internalId.toString();
    }

    function appOf(w) {
        return w.desktopFileName || w.resourceClass;
    }

    function manageable(w) {
        return !!w && w.pid !== -1 && w.normalWindow && w.managed && !w.deleted && !w.transient && !w.skipTaskbar
            && w.moveable && w.resizeable;
    }

    function isFree(w) {
        return config.free.indexOf(appOf(w)) >= 0;
    }

    function onDesktop(w) {
        return (w.onAllDesktops || w.desktops.indexOf(Workspace.currentDesktop) >= 0)
            && (!w.activities.length || w.activities.indexOf(Workspace.currentActivity) >= 0);
    }

    function save() {
        settings.displays = JSON.stringify(config.displays);
        settings.layouts = JSON.stringify(config.layouts);
        settings.rules = JSON.stringify(config.rules);
        settings.free = JSON.stringify(config.free);
        settings.last = JSON.stringify(config.last);
    }

    function saveWindows() {
        var windows = {};
        Object.keys(tracked).forEach(function (id) {
            var entry = tracked[id];
            if (!entry.preferred) return;
            windows[id] = { display: entry.display, zone: entry.zone, width: entry.preferred.width, height: entry.preferred.height, filled: entry.filled };
        });
        settings.windows = JSON.stringify(windows);
    }

    function outputBase(output) {
        return [output.manufacturer, output.model, output.serialNumber].filter(Boolean).join(" ") || output.name;
    }

    function outputKey(output) {
        var base = outputBase(output);
        var twins = Workspace.screens.filter(function (o) { return o !== output && outputBase(o) === base; });
        return twins.length ? base + " " + output.name : base;
    }

    function outputName(output) {
        return output.model ? output.name + " · " + output.model : output.name;
    }

    function surfaceList() {
        return Object.keys(surfaces).map(function (key) { return surfaces[key]; });
    }

    function surfaceAt(point) {
        return surfaceList().find(function (s) { return Geometry.contains(s.bounds, point); }) || null;
    }

    function barSize(side) {
        if (!Geometry.vertical(side)) return barHeight;
        return settings.compactTabs ? narrowWidth : sideWidth;
    }

    function placeZones(zones, area, displaySide) {
        return zones.map(function (z) {
            var side = Store.zoneSide(z, displaySide);
            return Geometry.place(z, area, side, barSize(side));
        });
    }

    function refreshGeometry() {
        hideZoneInfo();
        var next = {};
        Workspace.screens.forEach(function (output) {
            var key = outputKey(output);
            if (!config.displays[key]) return;
            var area = rectOf(Workspace.clientArea(Workspace.MaximizeArea, output, Workspace.currentDesktop));
            var side = Store.sideOf(config, key, settings.tabsAt);
            next[key] = {
                key: key,
                output: output,
                area: area,
                side: side,
                bounds: rectOf(output.geometry),
                others: Workspace.screens.filter(function (o) { return o !== output; }).map(function (o) { return rectOf(o.geometry); }),
                placed: placeZones(Store.zonesOf(config, key), area, side)
            };
        });
        surfaces = next;
    }

    function placement(entry) {
        var surface = surfaces[entry.display];
        if (!surface || !surface.placed.length) return null;
        var zone = Geometry.resolve(surface.placed, entry.zone) || Geometry.resolve(surface.placed, defaultZone);
        return { surface: surface, zone: zone };
    }

    function sizeOf(s) {
        return { width: s.width, height: s.height };
    }

    function place(id, fit, frameOverride) {
        var entry = tracked[id];
        var where = entry && placement(entry);
        if (!where) return;
        if (entry.window.fullScreen) {
            if (settings.zoneFullScreen) frameTo(entry, where.zone.full);
            return;
        }
        var w = entry.window;
        var frame = frameOverride || rectOf(w.frameGeometry);
        var content = where.zone.content;
        var result = Geometry.target(frame, content, where.surface.area, {
            fit: fit, filled: entry.filled, preferred: entry.preferred, minimum: sizeOf(w.minSize), maximum: sizeOf(w.maxSize),
            snap: settings.snap, side: where.zone.side, walls: Geometry.walls(content, where.surface.bounds, where.surface.others)
        });
        var resized = entry.known ? !Geometry.sameSize(entry.known, frame) : true;
        if (fit === "free" && resized) entry.preferred = sizeOf(result);
        else if (!entry.preferred) entry.preferred = sizeOf(frame);
        entry.known = result;
        var filled = Geometry.same(result, content);
        if (filled !== entry.filled) scheduleRedraw();
        entry.filled = filled;
        if (!Geometry.same(rectOf(w.frameGeometry), result)) request(entry, result);
        scheduleSave();
    }

    function frameTo(entry, frame) {
        if (!Geometry.same(rectOf(entry.window.frameGeometry), frame)) request(entry, frame);
    }

    function fullScreenRequested(w) {
        if (!running || paused || !settings.zoneFullScreen || w.fullScreen) return;
        var id = idOf(w);
        Qt.callLater(function () {
            var entry = tracked[id];
            var where = entry && placement(entry);
            if (where) frameTo(entry, where.zone.full);
        });
    }

    function fullScreenToggled(w) {
        var id = idOf(w);
        var entry = tracked[id];
        if (!running || paused || !settings.zoneFullScreen || !entry) return;
        if (w.fullScreen) {
            place(id, "keep");
            return;
        }
        var f = w.frameGeometry;
        entry.nudged = !entry.nudged;
        w.frameGeometry = Qt.rect(f.x + (entry.nudged ? restoreNudge : -restoreNudge), f.y, f.width, f.height);
    }

    function fitFullScreen() {
        Object.keys(tracked).forEach(function (id) {
            var entry = tracked[id];
            var where = placement(entry);
            if (where && entry.window.fullScreen) frameTo(entry, settings.zoneFullScreen ? where.zone.full : where.surface.bounds);
        });
    }

    function request(entry, frame) {
        entry.pendingUntil = Date.now() + pendingTime;
        pendingTimer.restart();
        entry.window.frameGeometry = Qt.rect(frame.x, frame.y, frame.width, frame.height);
    }

    function settlePending() {
        var now = Date.now();
        Object.keys(tracked).forEach(function (id) {
            var entry = tracked[id];
            if (!entry.pendingUntil || entry.pendingUntil > now) return;
            entry.pendingUntil = 0;
            if (!Geometry.same(rectOf(entry.window.frameGeometry), entry.known)) applyChange(entry.window);
        });
    }

    function recordZone(id) {
        var entry = tracked[id];
        if (!entry || Date.now() < holdUntil) return;
        if (Store.record(config, Store.displaySet(Object.keys(surfaces)), appOf(entry.window), entry.display, entry.zone)) save();
    }

    function adopt(w, display, zone, fit, frame) {
        if (isFree(w)) return;
        var id = idOf(w);
        var entry = tracked[id];
        if (!entry) {
            counter++;
            var restored = saved[id];
            delete saved[id];
            var home = restored && config.displays[restored.display] ? restored : null;
            if (home) fit = "keep";
            entry = tracked[id] = {
                window: w,
                display: home ? home.display : display,
                zone: home ? home.zone : zone,
                filled: restored ? restored.filled : false,
                preferred: restored ? { width: restored.width, height: restored.height } : null,
                known: null,
                restore: null,
                order: counter,
                pendingUntil: 0,
                nudged: false,
                unmaximizedAt: 0
            };
        } else {
            entry.display = display;
            entry.zone = zone;
        }
        recordZone(id);
        place(id, fit, frame);
        scheduleRedraw();
    }

    function release(id) {
        if (!tracked[id]) return;
        delete tracked[id];
        scheduleRedraw();
        scheduleSave();
    }

    function ruleTarget(w) {
        var rule = config.rules[appOf(w)];
        return rule ? Store.resolveRule(rule, surfaceList()) : null;
    }

    function lastTarget(w, point) {
        var set = config.last[Store.displaySet(Object.keys(surfaces))];
        var last = set && set[appOf(w)];
        if (!last) return null;
        var target = Store.resolveRule(last, surfaceList());
        if (target) return target;
        var surface = surfaceAt(point);
        return surface ? { display: surface.key, zone: last.zone } : null;
    }

    function zoneIdAt(surface, point) {
        var zone = Geometry.zoneAt(surface.placed, point);
        return zone ? zone.id : defaultZone;
    }

    function adoptExisting(w, applyRules) {
        if (!manageable(w) || isFree(w) || tracked[idOf(w)]) return;
        var frame = rectOf(w.frameGeometry);
        var rule = ruleTarget(w);
        var surface = surfaceAt(Geometry.center(frame));
        if (surface) {
            var ruled = rule && rule.display === surface.key ? rule.zone : null;
            adopt(w, surface.key, ruled || zoneIdAt(surface, Geometry.center(frame)), "arrive");
        } else if (applyRules && rule) {
            adopt(w, rule.display, rule.zone, "arrive");
        }
    }

    function adoptAll(applyRules) {
        Workspace.stackingOrder.forEach(function (w) { adoptExisting(w, applyRules); });
    }

    function windowCreated(w) {
        if (!running || paused || !manageable(w) || isFree(w)) return;
        var frame = rectOf(w.frameGeometry);
        var target = ruleTarget(w) || lastTarget(w, Geometry.center(frame));
        if (target) {
            adopt(w, target.display, target.zone, "arrive");
        } else {
            var surface = surfaceAt(Geometry.center(frame));
            if (surface) adopt(w, surface.key, defaultZone, "arrive");
        }
    }

    function frameChanged(w) {
        if (!running || paused || w.pid === -1) return;
        var id = idOf(w);
        updateCovers();
        changed[id] = w;
        if (!changeTimer.running) changeTimer.start();
    }

    function settleChanges() {
        var windows = changed;
        changed = {};
        Object.keys(windows).forEach(function (id) { applyChange(windows[id]); });
    }

    function applyChange(w) {
        if (!running || paused) return;
        if (w.dock) {
            panelMoved();
            return;
        }
        var id = idOf(w);
        var entry = tracked[id];
        if ((carry && carry.id === id) || w.move || w.resize || maximizing[id] || w.maximizeMode !== 0) return;
        var frame = rectOf(w.frameGeometry);
        var middle = Geometry.center(frame);
        if (entry) {
            if (entry.known && Geometry.same(frame, entry.known)) {
                entry.pendingUntil = 0;
                return;
            }
            if (Date.now() < entry.pendingUntil || Date.now() < holdUntil) return;
            if (w.fullScreen) {
                place(id, "keep");
                scheduleRedraw();
                return;
            }
            var home = surfaces[entry.display];
            if (home && Geometry.contains(home.bounds, middle)) {
                place(id, "free");
            } else {
                var other = surfaceAt(middle);
                if (other) {
                    entry.display = other.key;
                    entry.zone = zoneIdAt(other, middle);
                    recordZone(id);
                    place(id, "free");
                    scheduleRedraw();
                } else {
                    release(id);
                }
            }
        } else if (manageable(w) && !isFree(w)) {
            var surface = surfaceAt(middle);
            if (surface) adopt(w, surface.key, zoneIdAt(surface, middle), "arrive");
        }
    }

    function windowRemoved(w) {
        delete changed[idOf(w)];
        if (gesture && gesture.window === w) gesture = null;
        if (carry && carry.window === w) stopCarry();
        release(idOf(w));
        updateCovers();
    }

    function gestureStarted(w) {
        if (!running || paused) return;
        hideZoneInfo();
        var entry = tracked[idOf(w)];
        gesture = { window: w, old: entry && entry.known ? entry.known : rectOf(w.frameGeometry), down: pointOf(Workspace.cursorPos), resize: w.resize };
    }

    function gestureStepped(w, geometry) {
        if (!gesture || gesture.window !== w) return;
        gesture.last = rectOf(geometry);
        if (gesture.resize && !gesture.press) gesture.press = Geometry.pressPoint(gesture.old, gesture.last, pointOf(Workspace.cursorPos));
        if (gesture.resize && tracked[idOf(w)]) showSize(idOf(w));
    }

    function gestureFinished(w) {
        hideBadge();
        var g = gesture;
        gesture = null;
        lastGesture = { window: w, at: Date.now() };
        if (!running || paused || !g || g.window !== w) return;
        updateCovers();
        if (w.tile || w.maximizeMode !== 0) return;
        settle(w, g, pointOf(Workspace.cursorPos));
    }

    function settle(w, g, up) {
        var id = idOf(w);
        var entry = tracked[id];
        var old = g.old;
        var frame = g.last || rectOf(w.frameGeometry);
        if (!entry) {
            var surface = manageable(w) && !isFree(w) ? surfaceAt(Geometry.center(frame)) : null;
            if (surface) adopt(w, surface.key, zoneIdAt(surface, Geometry.contains(surface.bounds, up) ? up : Geometry.center(frame)), "keep");
            return;
        }
        var kind = Geometry.gesture(old, frame);
        if (kind === "resized") {
            if (!resizeZones(id, g.press || Geometry.pressPoint(old, frame, up), old, frame)) place(id, "free", frame);
        } else if (kind === "moved") {
            var home = surfaces[entry.display];
            if (!Geometry.contains(old, g.down)) {
                place(id, "keep", frame);
            } else if (home && Geometry.contains(home.bounds, up)) {
                place(id, "free", frame);
            } else {
                var other = surfaceAt(up);
                if (other) adopt(w, other.key, zoneIdAt(other, up), "keep", frame);
                else release(id);
            }
        }
    }

    function movedDividers(id, down, old, now) {
        if (settings.lockZones) return null;
        var entry = tracked[id];
        var where = placement(entry);
        if (!where || !Geometry.same(old, where.zone.content)) return null;
        var zones = Store.zonesOf(config, where.surface.key);
        var changed = false;
        Geometry.edgeMoves(old, now, down, where.surface.area, Geometry.margins(where.zone)).forEach(function (move) {
            var next = Geometry.moving(zones, move);
            if (!next) return;
            zones = next;
            changed = true;
        });
        return changed ? { surface: where.surface, zones: zones } : null;
    }

    function resizeZones(id, down, old, now) {
        var moved = movedDividers(id, down, old, now);
        if (!moved) return false;
        Store.setDraft(config, moved.surface.key, moved.zones);
        save();
        reflow();
        return true;
    }

    function maximizeChanging(w, mode) {
        var id = idOf(w);
        if (!running || paused || !tracked[id] || mode === 0 || maximizing[id]) return;
        maximizing[id] = true;
        Qt.callLater(function () { if (maximizing[id]) takeMaximize(id); });
    }

    function maximized(w) {
        var entry = tracked[idOf(w)];
        if (!entry || w.maximizeMode === 0 || Date.now() - entry.unmaximizedAt < pendingTime) return;
        takeMaximize(idOf(w));
    }

    function takeMaximize(id) {
        var entry = tracked[id];
        delete maximizing[id];
        if (!entry || !running || paused) return;
        var w = entry.window;
        var before = entry.known || rectOf(w.frameGeometry);
        var dropped = lastGesture && lastGesture.window === w && Date.now() - lastGesture.at < pendingTime;
        entry.unmaximizedAt = Date.now();
        w.setMaximize(false, false);
        if (dropped && entry.filled) place(id, "fill");
        else toggleFill(id, before);
    }

    function tileRequested(w) {
        var id = idOf(w);
        if (!running || paused || !tracked[id] || !w.tile) return;
        Qt.callLater(function () { if (tracked[id]) tiled(tracked[id].window); });
    }

    function tiled(w) {
        var id = idOf(w);
        if (!running || paused || !tracked[id] || !w.tile) return;
        w.tile = null;
        place(id, "fill");
    }

    function isFilled(entry) {
        return entry.filled || entry.window.fullScreen;
    }

    function toggleFill(id, from) {
        var entry = tracked[id];
        var where = entry && placement(entry);
        if (!where) return;
        if (entry.window.fullScreen) {
            entry.window.fullScreen = false;
            return;
        }
        var frame = from || rectOf(entry.window.frameGeometry);
        var content = where.zone.content;
        if (entry.filled) {
            var restore = entry.restore || Geometry.arrive(
                Geometry.rect(0, 0, Math.round(content.width * 0.7), Math.round(content.height * 0.7)), content, where.surface.area);
            entry.restore = null;
            place(id, "free", restore);
        } else {
            entry.restore = frame;
            place(id, "fill");
        }
        Workspace.activeWindow = entry.window;
        scheduleRedraw();
    }

    function center(id) {
        var entry = tracked[id];
        var where = entry && placement(entry);
        if (!where) return;
        place(id, "free", Geometry.centered(rectOf(entry.window.frameGeometry), where.zone.content, where.surface.area, where.zone.side));
        Workspace.activeWindow = entry.window;
    }

    function reflow() {
        refreshGeometry();
        Object.keys(tracked).forEach(function (id) { place(id, "keep"); });
        scheduleRedraw();
    }

    function hold() {
        holdUntil = Date.now() + 3000;
        holdTimer.restart();
    }

    function panelMoved() {
        var moved = surfaceList().some(function (s) {
            return !Geometry.same(rectOf(Workspace.clientArea(Workspace.MaximizeArea, s.output, Workspace.currentDesktop)), s.area);
        });
        if (moved) reflow();
    }

    function displaysChanged() {
        if (!running || paused) return;
        hold();
        refreshGeometry();
        scheduleRedraw();
    }

    function fullScreenOn(surface) {
        return Workspace.stackingOrder.some(function (w) {
            return w.fullScreen && !w.minimized && onDesktop(w) && !(settings.zoneFullScreen && tracked[idOf(w)])
                && Geometry.contains(surface.bounds, Geometry.center(rectOf(w.frameGeometry)));
        });
    }

    function zoneKey(entry) {
        var where = placement(entry);
        return where ? entry.display + "|" + where.zone.id : "";
    }

    function members(display, zone) {
        return Object.keys(tracked).filter(function (id) {
            var entry = tracked[id];
            var where = placement(entry);
            return entry.display === display && where && where.zone.id === zone && onDesktop(entry.window);
        }).sort(function (a, b) { return tracked[a].order - tracked[b].order; });
    }

    function scheduleRedraw() {
        if (!redrawTimer.running) redrawTimer.start();
    }

    function scheduleSave() {
        if (!saveTimer.running) saveTimer.start();
    }

    function redraw() {
        if (!running || paused || !surfaceList().length) {
            closeBars();
            return;
        }
        var stack = Workspace.stackingOrder;
        var rank = {};
        stack.forEach(function (w, index) { if (w.pid !== -1) rank[idOf(w)] = index; });
        var keys = {};
        var shown = surfaceList().filter(function (s) { return !fullScreenOn(s); });
        shown.forEach(function (surface) {
            surface.placed.forEach(function (zone) {
                var key = surface.key + "|" + zone.id;
                keys[key] = true;
                var ids = members(surface.key, zone.id);
                var active = null;
                ids.forEach(function (id) {
                    if (!tracked[id].window.minimized && (active === null || rank[id] > rank[active])) active = id;
                });
                var bar = bars[key] || makeBar(key, surface.key, zone.id);
                bar.label = zone.id;
                bar.side = zone.side;
                bar.compact = settings.compactTabs;
                bar.expandable = settings.compactTabs && Geometry.vertical(zone.side);
                bar.leftLine = settings.borders && zone.bar.x === zone.full.x && zone.full.x > surface.area.x + Geometry.pixelTolerance;
                bar.topLine = settings.borders && zone.bar.y === zone.full.y && zone.full.y > surface.area.y + Geometry.pixelTolerance;
                bar.tabs = ids.map(function (id) {
                    var w = tracked[id].window;
                    return { id: id, title: w.caption || appLabel(appOf(w)), icon: w.icon, active: id === active, minimized: w.minimized, filled: isFilled(tracked[id]) };
                });
                bar.zone = zone.bar;
                bar.wide = Geometry.widened(zone, zone.side, sideWidth);
            });
        });
        Object.keys(bars).forEach(function (key) {
            if (keys[key]) return;
            bars[key].destroy();
            delete bars[key];
        });
        var rects = settings.borders ? [].concat.apply([], shown.map(function (s) {
            return Geometry.uncovered(Geometry.dividers(s.placed, s.area, lineWidth), s.placed.map(function (p) { return p.bar; }));
        })) : [];
        while (lines.length > rects.length) lines.pop().destroy();
        rects.forEach(function (r, index) {
            var line = lines[index] || (lines[index] = overlay(shadeComponent, { fill: "#6b6b6b" }));
            show(line, r);
        });
        updateCovers();
    }

    function overlay(component, properties) {
        var made = component.createObject(null, properties || {});
        made.title += " " + (++overlays);
        return made;
    }

    function frameOf(window) {
        return Workspace.stackingOrder.find(function (w) { return w.pid === -1 && w.caption === window.title; }) || null;
    }

    function show(window, r) {
        if (!window.visible) window.visible = true;
        var frame = frameOf(window);
        if (frame) {
            if (!Geometry.same(rectOf(frame.frameGeometry), r, 0.5)) frame.frameGeometry = Qt.rect(r.x, r.y, r.width, r.height);
        } else if (!Geometry.same(rectOf(window), r, 0.5)) {
            window.width = r.width;
            window.height = r.height;
            window.x = r.x;
            window.y = r.y;
        }
    }

    function updateCovers() {
        var keys = Object.keys(bars);
        if (!keys.length) return;
        var others = Workspace.stackingOrder.filter(function (w) {
            return w.pid !== -1 && !w.desktopWindow && !w.minimized && !w.hidden && onDesktop(w);
        });
        keys.forEach(function (key) {
            var bar = bars[key];
            bar.blockers = others.filter(function (w) {
                var entry = tracked[idOf(w)];
                return !(entry && zoneKey(entry) === key && !w.move && !w.resize && !w.fullScreen);
            }).map(function (w) { return rectOf(w.frameGeometry); });
            showBar(bar);
        });
    }

    function showBar(bar) {
        var full = bar.expanded ? bar.wide : bar.zone;
        var part = Geometry.visiblePart(full, bar.blockers, bar.vertical);
        bar.covered = !part;
        bar.fullWidth = full.width;
        bar.fullHeight = full.height;
        bar.offset = part ? (bar.vertical ? part.y - full.y : part.x - full.x) : 0;
        show(bar, part || full);
    }

    function makeBar(key, display, zone) {
        var bar = overlay(barComponent, { zone: Geometry.rect(0, 0, 1, 1) });
        bar.select.connect(function (id) { select(id); });
        bar.carry.connect(function (id) { dragTab(id); });
        bar.drop.connect(function (id) { dropTab(id); });
        bar.reorder.connect(function (id, index) { reorderTab(id, index); });
        bar.tabMenu.connect(function (id) { openTabMenu(id); });
        bar.press.connect(function (id, button) { pressButton(id, button); });
        bar.labelClicked.connect(function () { toggleZoneInfo(display, zone); });
        bar.labelMenu.connect(function () { openMenu(display, zone); });
        bar.expandedChanged.connect(function () { showBar(bar); });
        bars[key] = bar;
        return bar;
    }

    function closeBars() {
        Object.keys(bars).forEach(function (key) { bars[key].destroy(); });
        bars = {};
        lines.forEach(function (line) { line.destroy(); });
        lines = [];
        hideGhost();
        hideBadge();
    }

    function select(id) {
        var entry = tracked[id];
        if (!entry) return;
        if (entry.window.minimized) entry.window.minimized = false;
        Workspace.activeWindow = entry.window;
        scheduleRedraw();
    }

    function pressButton(id, button) {
        var entry = tracked[id];
        if (!entry) return;
        if (button === "close") entry.window.closeWindow();
        else if (button === "minimize") entry.window.minimized = true;
        else toggleFill(id);
    }

    function dragTab(id) {
        var cursor = pointOf(Workspace.cursorPos);
        showGhost(cursor);
        if (!carry) {
            var entry = tracked[id];
            if (!entry) return;
            var w = entry.window;
            if (w.minimized) w.minimized = false;
            var frame = rectOf(w.frameGeometry);
            carry = { id: id, window: w, start: frame, grip: { x: Math.round(frame.width / 2), y: 12 } };
            Workspace.raiseWindow(w);
        }
        if (!carryTimer.running) carryTimer.start();
    }

    function moveCarried() {
        if (!carry) return;
        var cursor = pointOf(Workspace.cursorPos);
        var frame = rectOf(carry.window.frameGeometry);
        carry.window.frameGeometry = Qt.rect(cursor.x - carry.grip.x, cursor.y - carry.grip.y, frame.width, frame.height);
    }

    function stopCarry() {
        carry = null;
        carryTimer.stop();
    }

    function dropTab(id) {
        hideGhost();
        var entry = tracked[id];
        if (!entry) return;
        var carried = carry;
        stopCarry();
        var point = pointOf(Workspace.cursorPos);
        var w = entry.window;
        var frame = rectOf(w.frameGeometry);
        if (carried) frame = Geometry.rect(point.x - carried.grip.x, point.y - carried.grip.y, frame.width, frame.height);
        var surface = surfaceAt(point);
        var zone = surface && Geometry.zoneAt(surface.placed, point);
        if (zone) {
            adopt(w, surface.key, zone.id, "keep", frame);
            Workspace.activeWindow = w;
        } else {
            if (carried) w.frameGeometry = Qt.rect(frame.x, frame.y, frame.width, frame.height);
            release(id);
        }
    }

    function reorderTab(id, index) {
        hideGhost();
        if (carry) {
            var start = carry.start;
            var w = carry.window;
            stopCarry();
            w.frameGeometry = Qt.rect(start.x, start.y, start.width, start.height);
        }
        var entry = tracked[id];
        var where = entry && placement(entry);
        if (!where) return;
        var ids = members(entry.display, where.zone.id);
        var current = ids.indexOf(id);
        if (current < 0 || current === index || index < 0 || index >= ids.length) return;
        ids.splice(current, 1);
        ids.splice(index, 0, id);
        ids.forEach(function (member) { tracked[member].order = ++counter; });
        redraw();
    }

    function showGhost(point) {
        var surface = surfaceAt(point);
        var zone = surface && Geometry.zoneAt(surface.placed, point);
        var key = zone ? surface.key + "|" + zone.id : "";
        if (key === ghostKey) return;
        ghostKey = key;
        if (!zone) {
            hideGhost();
            return;
        }
        if (!ghost) ghost = overlay(shadeComponent, { fill: "#40386bd1", radius: 6 });
        ghost.border.color = "#e6386bd1";
        ghost.border.width = 3;
        show(ghost, zone.full);
    }

    function hideGhost() {
        ghostKey = "";
        if (ghost) ghost.destroy();
        ghost = null;
    }

    function formatSize(width, height) {
        return Math.round(width) + " × " + Math.round(height) + " px";
    }

    function showBadge(lines, place) {
        if (!badge) badge = overlay(badgeComponent);
        badge.lines = lines;
        var size = badge.measure();
        var origin = place(size.width, size.height);
        show(badge, Geometry.rect(origin.x, origin.y, size.width, size.height));
    }

    function hideBadge() {
        zoneInfo = "";
        if (badge) badge.destroy();
        badge = null;
    }

    function hideZoneInfo() {
        if (zoneInfo) hideBadge();
    }

    function showSize(id) {
        zoneInfo = "";
        var entry = tracked[id];
        var where = placement(entry);
        var frame = gesture && gesture.last ? gesture.last : rectOf(entry.window.frameGeometry);
        if (!where || !entry.known || !gesture || Geometry.gesture(entry.known, frame) !== "resized") {
            hideBadge();
            return;
        }
        var info = [];
        var moved = movedDividers(id, gesture.press || Geometry.pressPoint(entry.known, frame, pointOf(Workspace.cursorPos)), entry.known, frame);
        if (moved) {
            placeZones(moved.zones, where.surface.area, where.surface.side).forEach(function (zone) {
                var before = where.surface.placed.find(function (p) { return p.id === zone.id; });
                if (before && Geometry.sameSize(before.full, zone.full)) return;
                info.push({ label: "Zona " + zone.id, value: formatSize(zone.full.width, zone.full.height) });
            });
        }
        var scale = where.surface.output.devicePixelRatio;
        info.push({ label: "Ventana", value: formatSize(frame.width, frame.height) });
        info.push({ label: "Físicos", value: formatSize(frame.width * scale, frame.height * scale) });
        var cursor = pointOf(Workspace.cursorPos);
        var screen = surfaceAt(cursor) ? surfaceAt(cursor).bounds : where.surface.bounds;
        showBadge(info, function (width, height) {
            var gap = 16;
            var x = cursor.x + gap + width <= Geometry.maxX(screen) ? cursor.x + gap : cursor.x - gap - width;
            var y = cursor.y + gap + height <= Geometry.maxY(screen) ? cursor.y + gap : cursor.y - gap - height;
            return { x: Math.round(x), y: Math.round(y) };
        });
    }

    function toggleZoneInfo(display, id) {
        var key = display + "|" + id;
        var surface = surfaces[display];
        var zone = surface && surface.placed.find(function (p) { return p.id === id; });
        var fraction = Store.zonesOf(config, display).find(function (z) { return z.id === id; });
        if (zoneInfo === key || !zone || !fraction) {
            hideBadge();
            return;
        }
        var scale = surface.output.devicePixelRatio;
        showBadge([
            { label: "Zona " + id, value: formatSize(zone.full.width, zone.full.height) },
            { label: "Físicos", value: formatSize(zone.full.width * scale, zone.full.height * scale) },
            { label: "Porcentaje", value: Math.round(fraction.w * 100) + " % × " + Math.round(fraction.h * 100) + " %" }
        ], function (width, height) {
            var x = zone.side === "right" ? zone.bar.x - 4 - width : zone.content.x + 4;
            var y = zone.side === "bottom" ? zone.bar.y - 4 - height : zone.content.y + 4;
            return {
                x: Math.min(Math.max(x, surface.bounds.x), Geometry.maxX(surface.bounds) - width),
                y: Math.min(Math.max(y, surface.bounds.y), Geometry.maxY(surface.bounds) - height)
            };
        });
        zoneInfo = key;
    }

    function setEnabled(output, enabled) {
        var key = outputKey(output);
        if (enabled) {
            Store.enable(config, key);
        } else {
            Store.disable(config, key);
            Object.keys(tracked).forEach(function (id) { if (tracked[id].display === key) delete tracked[id]; });
        }
        save();
        refreshGeometry();
        adoptAll(enabled);
        scheduleRedraw();
    }

    function setLayout(name, key) {
        Store.choose(config, key, name);
        save();
        reflow();
    }

    function openEditor(key, heading, zones, onSave) {
        var surface = surfaces[key];
        if (!surface) return;
        if (editor) editor.finish(false);
        var opened = overlay(editorComponent, {
            heading: heading, zones: zones, panelScale: surface.output.devicePixelRatio
        });
        opened.saved.connect(function (result) {
            onSave(result);
            save();
            reflow();
        });
        opened.closed.connect(function () {
            if (editor === opened) editor = null;
            opened.destroy();
        });
        editor = opened;
        show(opened, surface.area);
        opened.requestActivate();
    }

    function ask(heading, message, text, acceptLabel, asksText, onAccept) {
        var dialog = overlay(dialogComponent, {
            heading: heading, message: message, text: text, acceptLabel: acceptLabel, asksText: asksText
        });
        dialog.accepted.connect(function (value) { Qt.callLater(onAccept, value); });
        var cursor = pointOf(Workspace.cursorPos);
        var surface = surfaceAt(cursor);
        var bounds = surface ? surface.area : rectOf(Workspace.activeScreen.geometry);
        show(dialog, Geometry.rect(Math.round(Geometry.midX(bounds) - dialog.width / 2), Math.round(Geometry.midY(bounds) - dialog.height / 2), dialog.width, dialog.height));
        dialog.requestActivate();
    }

    function newLayout(key) {
        ask("Nueva disposición", "", Store.nextName(config), "Crear", true, function (name) {
            openEditor(key, name, Store.single.zones, function (zones) {
                Store.choose(config, key, Store.add(config, { name: name, zones: zones }));
            });
        });
    }

    function editZones(key) {
        var layout = Store.layoutNamed(config, config.displays[key].layout);
        if (layout.name === Store.single.name) return;
        var heading = Store.hasDraft(config, key) ? layout.name + " (sin guardar)" : layout.name;
        openEditor(key, heading, Store.zonesOf(config, key), function (zones) { Store.setZones(config, layout.name, zones); });
    }

    function renameLayout(name) {
        ask("Renombrar «" + name + "»", "", name, "Renombrar", true, function (proposed) {
            Store.rename(config, name, proposed);
            save();
        });
    }

    function removeLayout(name) {
        ask("¿Eliminar «" + name + "»?", "Las pantallas que la usan pasan a " + Store.single.name + ".", "", "Eliminar", false, function () {
            Store.remove(config, name);
            save();
            reflow();
        });
    }

    function setRule(app, rule) {
        var wasFree = Store.setRule(config, app, rule);
        save();
        Workspace.stackingOrder.forEach(function (w) {
            if (!manageable(w) || appOf(w) !== app) return;
            var target = rule && Store.resolveRule(rule, surfaceList());
            if (target) adopt(w, target.display, target.zone, "arrive");
            else if (wasFree) adoptExisting(w, false);
        });
    }

    function setFree(app) {
        Store.setFree(config, app);
        save();
        Object.keys(tracked).forEach(function (id) { if (appOf(tracked[id].window) === app) release(id); });
    }

    function setPaused(value) {
        paused = value;
        if (value) {
            stopCarry();
            closeBars();
        } else {
            refreshGeometry();
            adoptAll(false);
            reflow();
        }
    }

    function setOption(name, value) {
        settings[name] = value;
        if (name === "snap") Object.keys(tracked).forEach(function (id) { place(id, "free"); });
        if (name === "tabsAt" || name === "compactTabs") reflow();
        if (name === "zoneFullScreen") fitFullScreen();
        scheduleRedraw();
    }

    function setDisplaySide(key, side) {
        Store.setSide(config, key, side);
        save();
        reflow();
    }

    function sideItems(parentMenu, current, choose) {
        Store.sides.forEach(function (side) {
            item(parentMenu, sideNames[side], function () { choose(side); }, side === current);
        });
    }

    function item(parentMenu, text, action, checked, enabled) {
        var made = menuItemComponent.createObject(parentMenu, {
            text: text, checkable: checked !== undefined, checked: !!checked, enabled: enabled !== false
        });
        if (action) made.triggered.connect(function () {
            menuOpened = 0;
            action();
        });
        parentMenu.addItem(made);
        return made;
    }

    function separator(parentMenu) {
        parentMenu.addItem(menuSeparatorComponent.createObject(parentMenu));
    }

    function submenu(parentMenu, title) {
        var made = menuComponent.createObject(parentMenu, { title: title });
        parentMenu.addMenu(made);
        return made;
    }

    function newMenu() {
        if (menu) menu.destroy();
        menu = menuComponent.createObject(root);
        menu.aboutToHide.connect(function () {
            menuHidden = true;
            Qt.callLater(reopenMenu);
        });
        return menu;
    }

    function showMenu() {
        menuOpened = Date.now();
        menu.open();
    }

    function reopenMenu() {
        var interrupted = menuHidden && focusMoved && Date.now() - menuOpened < reopenWithin;
        menuHidden = false;
        focusMoved = false;
        if (!interrupted) return;
        menuOpened = 0;
        menu.open();
    }

    function setZoneSide(display, id, side) {
        Store.setZoneSide(config, display, id, side);
        save();
        reflow();
    }

    function appLabel(app) {
        var name = app.split(".").pop();
        return name.charAt(0).toUpperCase() + name.slice(1);
    }

    function zoneBarMenu(parentMenu, title, display, id) {
        var screen = config.displays[display];
        var zone = screen && Store.zonesOf(config, display).find(function (z) { return z.id === id; });
        if (!zone) return;
        var single = Store.layoutNamed(config, screen.layout).name === Store.single.name;
        var own = single ? screen.tabsAt : zone.tabsAt;
        var inherited = single ? Store.sideOf(config, "", settings.tabsAt) : Store.sideOf(config, display, settings.tabsAt);
        var sub = submenu(parentMenu, title);
        item(sub, "Como la pantalla (" + sideNames[inherited].toLowerCase() + ")", function () { setZoneSide(display, id, null); }, !own);
        separator(sub);
        sideItems(sub, own, function (side) { setZoneSide(display, id, side); });
    }

    function displayMenu(parentMenu, output) {
        var key = outputKey(output);
        var display = config.displays[key];
        var current = display ? Store.layoutNamed(config, display.layout).name : "";
        var unsaved = Store.hasDraft(config, key);
        var sub = submenu(parentMenu, outputName(output) + " — " + (display ? current + (unsaved ? " (sin guardar)" : "") : "sin zonas"));
        item(sub, "Usar zonas en esta pantalla", function () { setEnabled(output, !display); }, !!display);
        if (!display) return;
        separator(sub);
        Store.choices(config).forEach(function (layout) {
            var label = unsaved && layout.name === current ? layout.name + " (sin guardar)" : layout.name;
            item(sub, label, function () { setLayout(layout.name, key); }, layout.name === current);
        });
        separator(sub);
        var own = submenu(sub, "Barra de pestañas");
        item(own, "Como las demás (" + sideNames[Store.sideOf(config, "", settings.tabsAt)].toLowerCase() + ")", function () { setDisplaySide(key, null); }, !display.tabsAt);
        separator(own);
        sideItems(own, display.tabsAt, function (side) { setDisplaySide(key, side); });
        separator(sub);
        if (current !== Store.single.name) {
            var manage = submenu(sub, "«" + current + "»");
            item(manage, "Editar…", function () { editZones(key); });
            if (unsaved) item(manage, "Descartar los cambios sin guardar", function () { Store.discardDraft(config, key); save(); reflow(); });
            item(manage, "Renombrar…", function () { renameLayout(current); });
            item(manage, "Eliminar…", function () { removeLayout(current); });
        }
        item(sub, "Nueva disposición…", function () { newLayout(key); });
    }

    function openMenu(display, zone) {
        var menu = newMenu();
        var here = display ? surfaces[display] : null;
        if (here) {
            item(menu, "Zona " + zone + " · " + outputName(here.output), null, undefined, false);
            zoneBarMenu(menu, "Barra de esta zona", display, zone);
            separator(menu);
        }
        Workspace.screens.slice().sort(function (a, b) { return a.geometry.x - b.geometry.x; }).forEach(function (output) {
            displayMenu(menu, output);
        });
        separator(menu);
        var tabsMenu = submenu(menu, "Barra de pestañas");
        sideItems(tabsMenu, Store.sideOf(config, "", settings.tabsAt), function (side) { setOption("tabsAt", side); });
        separator(tabsMenu);
        item(tabsMenu, "Compacta", function () { setOption("compactTabs", !settings.compactTabs); }, settings.compactTabs);
        item(menu, "Mostrar bordes de las zonas", function () { setOption("borders", !settings.borders); }, settings.borders);
        separator(menu);
        item(menu, "Bloquear el tamaño de las zonas", function () { setOption("lockZones", !settings.lockZones); }, settings.lockZones);
        item(menu, "Imantar las ventanas a su zona", function () { setOption("snap", !settings.snap); }, settings.snap);
        item(menu, "Pantalla completa dentro de la zona", function () { setOption("zoneFullScreen", !settings.zoneFullScreen); }, settings.zoneFullScreen);
        var free = submenu(menu, "Apps libres");
        if (!config.free.length) item(free, "Ninguna", null, undefined, false);
        config.free.slice().sort().forEach(function (app) {
            item(free, appLabel(app), function () { setRule(app, null); }, true);
        });
        separator(menu);
        item(menu, paused ? "Reanudar" : "Pausar", function () { setPaused(!paused); });
        showMenu();
    }

    function openTabMenu(id) {
        var entry = tracked[id];
        if (!entry) return;
        var menu = newMenu();
        var app = appOf(entry.window);
        var name = appLabel(app);
        var rule = config.rules[app];
        var where = placement(entry);
        item(menu, isFilled(entry) ? "Volver al tamaño anterior" : "Maximizar en la zona", function () { toggleFill(id); });
        item(menu, "Centrar en la zona", function () { center(id); });
        item(menu, "Minimizar", function () { entry.window.minimized = true; });
        item(menu, "Cerrar", function () { entry.window.closeWindow(); });
        separator(menu);
        if (where) {
            zoneBarMenu(menu, "Barra de la zona " + where.zone.id, entry.display, where.zone.id);
            separator(menu);
        }
        var opens = submenu(menu, "Abrir " + name + " en");
        item(opens, "La última zona que usó", function () { setRule(app, null); }, !rule);
        separator(opens);
        var displays = surfaceList().sort(function (a, b) { return a.bounds.x - b.bounds.x; });
        var leftmost = displays.length ? displays[0].key : "";
        displays.forEach(function (surface) {
            var target = displays.length === 1 ? opens : submenu(opens, outputName(surface.output));
            Store.zonesOf(config, surface.key).forEach(function (z) {
                var checked = !!rule && rule.zone === z.id && (rule.display || leftmost) === surface.key;
                item(target, "Zona " + z.id, function () { setRule(app, { display: surface.key, zone: z.id }); }, checked);
            });
        });
        item(menu, name + " ignora las zonas", function () { setFree(app); });
        showMenu();
    }

    function start() {
        config = Store.load({
            displays: settings.displays, layouts: settings.layouts, rules: settings.rules,
            free: settings.free, last: settings.last
        });
        saved = Store.parse(settings.windows, {});
        running = true;
        refreshGeometry();
        adoptAll(false);
        saved = {};
        scheduleSave();
        scheduleRedraw();
    }

    Component {
        id: menuItemComponent
        P.MenuItem {}
    }

    Component {
        id: menuSeparatorComponent
        P.MenuSeparator {}
    }

    Component {
        id: menuComponent
        P.Menu {}
    }

    Component {
        id: barComponent
        Bar {
            property var zone
            property var wide
        }
    }

    Component {
        id: shadeComponent
        Shade {}
    }

    Component {
        id: badgeComponent
        Badge {}
    }

    Component {
        id: editorComponent
        Editor {}
    }

    Component {
        id: dialogComponent
        Dialog {}
    }

    Timer {
        id: redrawTimer
        interval: 100
        onTriggered: root.redraw()
    }

    Timer {
        id: saveTimer
        interval: 1000
        onTriggered: root.saveWindows()
    }

    Timer {
        id: holdTimer
        interval: 3000
        onTriggered: {
            if (!root.running || root.paused) return;
            root.reflow();
            root.adoptAll(false);
        }
    }

    Timer {
        id: changeTimer
        interval: 50
        onTriggered: root.settleChanges()
    }

    Timer {
        id: pendingTimer
        interval: root.pendingTime + 50
        onTriggered: root.settlePending()
    }

    Timer {
        id: carryTimer
        interval: 16
        repeat: true
        onTriggered: root.moveCarried()
    }

    ShortcutHandler {
        name: "ScreenZones Menu"
        text: "ScreenZones: abrir el menú"
        sequence: ""
        onActivated: root.openMenu()
    }

    Instantiator {
        model: WindowModel {}
        delegate: Connections {
            target: model.window
            function onFrameGeometryChanged() { root.frameChanged(target); }
            function onInteractiveMoveResizeStarted() { root.gestureStarted(target); }
            function onInteractiveMoveResizeStepped(geometry) { root.gestureStepped(target, geometry); }
            function onInteractiveMoveResizeFinished() { root.gestureFinished(target); }
            function onMaximizedAboutToChange(mode) { root.maximizeChanging(target, mode); }
            function onMaximizedChanged() { root.maximized(target); }
            function onRequestedTileChanged() { root.tileRequested(target); }
            function onTileChanged() { root.tiled(target); }
            function onFullscreenGeometryRestoreChanged() { root.fullScreenRequested(target); }
            function onFullScreenChanged() {
                root.fullScreenToggled(target);
                root.frameChanged(target);
                root.scheduleRedraw();
            }
            function onMinimizedChanged() { root.scheduleRedraw(); }
            function onCaptionChanged() { root.scheduleRedraw(); }
            function onDesktopsChanged() { root.scheduleRedraw(); }
        }
    }

    Connections {
        target: Workspace
        function onWindowAdded(w) {
            root.windowCreated(w);
            root.updateCovers();
        }
        function onWindowRemoved(w) { root.windowRemoved(w); }
        function onWindowActivated() {
            root.focusMoved = true;
            Qt.callLater(root.reopenMenu);
            root.hideZoneInfo();
            root.scheduleRedraw();
        }
        function onScreensChanged() { root.displaysChanged(); }
        function onVirtualScreenGeometryChanged() { root.displaysChanged(); }
        function onCurrentDesktopChanged() {
            root.refreshGeometry();
            root.scheduleRedraw();
        }
        function onCurrentActivityChanged() { root.scheduleRedraw(); }
    }

    Component.onCompleted: start()

    Component.onDestruction: {
        running = false;
        saveWindows();
        if (menu) menu.destroy();
        closeBars();
        if (editor) editor.destroy();
    }
}
