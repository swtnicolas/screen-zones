var single = { name: "Una columna", zones: [{ id: "A", x: 0, y: 0, w: 1, h: 1 }] };
var sides = ["top", "bottom", "left", "right"];

function side(value) {
    return sides.indexOf(value) >= 0 ? value : null;
}

function parse(text, fallback) {
    try {
        var value = JSON.parse(text);
        return value === null || value === undefined ? fallback : value;
    } catch (e) {
        return fallback;
    }
}

function display(saved) {
    return {
        layout: typeof saved.layout === "string" ? saved.layout : single.name,
        draft: Array.isArray(saved.draft) ? saved.draft : null,
        tabsAt: side(saved.tabsAt)
    };
}

function load(raw) {
    var displays = {};
    var saved = parse(raw.displays, {});
    Object.keys(saved).forEach(function (key) { displays[key] = display(saved[key]); });
    return {
        displays: displays,
        layouts: parse(raw.layouts, []),
        rules: parse(raw.rules, {}),
        free: parse(raw.free, []),
        last: parse(raw.last, {})
    };
}

function sameZones(a, b) {
    return a.length === b.length && a.every(function (z, i) {
        var o = b[i];
        return z.id === o.id && z.x === o.x && z.y === o.y && z.w === o.w && z.h === o.h && (z.tabsAt || null) === (o.tabsAt || null);
    });
}

function unique(name, names) {
    var taken = names.concat([single.name]).map(function (n) { return n.toLowerCase(); });
    if (taken.indexOf(name.toLowerCase()) < 0) return name;
    for (var i = 2; ; i++) {
        var candidate = name + " " + i;
        if (taken.indexOf(candidate.toLowerCase()) < 0) return candidate;
    }
}

function choices(state) {
    return [single].concat(state.layouts);
}

function layoutNamed(state, name) {
    return state.layouts.find(function (l) { return l.name === name; }) || single;
}

function zonesOf(state, key) {
    var config = state.displays[key];
    if (!config) return single.zones;
    return config.draft || layoutNamed(state, config.layout).zones;
}

function hasDraft(state, key) {
    return !!(state.displays[key] && state.displays[key].draft);
}

function setDraft(state, key, zones) {
    var config = state.displays[key];
    if (!config) return;
    config.draft = sameZones(zones, layoutNamed(state, config.layout).zones) ? null : zones;
}

function discardDraft(state, key) {
    if (state.displays[key]) state.displays[key].draft = null;
}

function choose(state, key, name) {
    var config = state.displays[key];
    if (!config) return;
    config.layout = name;
    config.draft = null;
}

function setZones(state, name, zones) {
    var layout = state.layouts.find(function (l) { return l.name === name; });
    if (!layout) return;
    layout.zones = zones;
    Object.keys(state.displays).forEach(function (key) {
        if (state.displays[key].layout === name) state.displays[key].draft = null;
    });
}

function add(state, layout) {
    var name = unique(layout.name, state.layouts.map(function (l) { return l.name; }));
    state.layouts.push({ name: name, zones: layout.zones });
    return name;
}

function rename(state, name, proposed) {
    var layout = state.layouts.find(function (l) { return l.name === name; });
    if (proposed === name || !layout) return;
    var renamed = unique(proposed, state.layouts.filter(function (l) { return l.name !== name; }).map(function (l) { return l.name; }));
    layout.name = renamed;
    Object.keys(state.displays).forEach(function (key) {
        if (state.displays[key].layout === name) state.displays[key].layout = renamed;
    });
}

function remove(state, name) {
    state.layouts = state.layouts.filter(function (l) { return l.name !== name; });
    Object.keys(state.displays).forEach(function (key) {
        var config = state.displays[key];
        if (config.layout !== name) return;
        config.layout = single.name;
        config.draft = null;
    });
}

function nextName(state) {
    return unique("Disposición " + (state.layouts.length + 1), state.layouts.map(function (l) { return l.name; }));
}

function enable(state, key) {
    if (!state.displays[key]) state.displays[key] = display({});
}

function disable(state, key) {
    delete state.displays[key];
}

function resolveRule(rule, surfaces) {
    if (rule.display) {
        return surfaces.some(function (s) { return s.key === rule.display; }) ? { display: rule.display, zone: rule.zone } : null;
    }
    var ordered = surfaces.slice().sort(function (a, b) { return a.bounds.x - b.bounds.x; });
    var surface = ordered.find(function (s) { return s.placed.some(function (p) { return p.id === rule.zone; }); }) || ordered[0];
    return surface ? { display: surface.key, zone: rule.zone } : null;
}

function displaySet(keys) {
    return keys.slice().sort().join(" ");
}

function record(state, set, app, display, zone) {
    var zones = state.last[set] || (state.last[set] = {});
    var previous = zones[app];
    if (previous && previous.display === display && previous.zone === zone) return false;
    zones[app] = { display: display, zone: zone };
    return true;
}

function setRule(state, app, rule) {
    if (rule) state.rules[app] = rule; else delete state.rules[app];
    var wasFree = state.free.indexOf(app) >= 0;
    state.free = state.free.filter(function (a) { return a !== app; });
    return wasFree;
}

function setFree(state, app) {
    delete state.rules[app];
    if (state.free.indexOf(app) < 0) state.free.push(app);
}

function sideOf(state, key, general) {
    var config = state.displays[key];
    return (config && config.tabsAt) || side(general) || "top";
}

function setSide(state, key, value) {
    if (state.displays[key]) state.displays[key].tabsAt = side(value);
}

function zoneSide(zone, displaySide) {
    return side(zone.tabsAt) || displaySide;
}

function setZoneSide(state, key, id, value) {
    var config = state.displays[key];
    if (!config) return;
    var layout = state.layouts.find(function (l) { return l.name === config.layout; });
    if (!layout) {
        setSide(state, key, value);
        return;
    }
    var drafts = Object.keys(state.displays).map(function (k) { return state.displays[k]; }).filter(function (d) {
        return d.layout === layout.name && d.draft;
    }).map(function (d) { return d.draft; });
    [layout.zones].concat(drafts).forEach(function (zones) {
        zones.forEach(function (z) {
            if (z.id !== id) return;
            if (side(value)) z.tabsAt = value; else delete z.tabsAt;
        });
    });
}
