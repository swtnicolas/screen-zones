import QtQuick
import QtQuick.Window as QW
import org.kde.kirigami as Kirigami
import "../code/geometry.js" as Geometry

QW.Window {
    id: bar

    property string label
    property var tabs: []
    property string side: "top"
    property bool compact
    property bool expandable
    property bool expanded
    property bool leftLine
    property bool topLine
    property bool covered
    property bool outputOnly: covered
    property real fullWidth: width
    property real fullHeight: height
    property real offset
    property var blockers: []

    signal select(string id)
    signal carry(string id)
    signal drop(string id)
    signal reorder(string id, int index)
    signal tabMenu(string id)
    signal press(string id, string button)
    signal labelClicked()
    signal labelMenu()

    readonly property bool vertical: Geometry.vertical(side)
    readonly property int rowHeight: 22
    readonly property int labelWidth: 26
    readonly property int labelExtent: vertical ? rowHeight : labelWidth
    readonly property int maximumTab: 240
    readonly property int iconWidth: rowHeight + 6
    readonly property int buttonSize: 18
    readonly property int buttonStep: 20
    readonly property int buttonInset: 4
    readonly property int buttonsWidth: buttonInset + buttonStep * 2 + buttonSize + 4
    readonly property var buttonNames: ["minimize", "fill", "close"]
    readonly property bool titled: vertical ? fullWidth - 2 > iconWidth : true
    readonly property var widths: vertical
        ? Geometry.tabWidths(tabs.map(function (t) { return t.active; }), false, fullHeight - labelExtent, iconWidth, rowHeight + 2)
        : Geometry.tabWidths(tabs.map(function (t) { return t.active; }), compact, fullWidth - labelWidth, iconWidth, maximumTab)
    readonly property var starts: {
        var at = labelExtent;
        return widths.map(function (w) { var start = at; at += w; return start; });
    }
    readonly property int activeIndex: tabs.findIndex(function (t) { return t.active; })

    title: "ScreenZones bar"
    flags: Qt.FramelessWindowHint | Qt.WindowDoesNotAcceptFocus
    color: "#121c38"
    opacity: covered ? 0 : 1

    onExpandableChanged: if (!expandable) expanded = false
    onTabsChanged: mouse.track()

    function tabRect(i) {
        if (vertical) return Qt.rect(side === "right" ? 2 : 0, starts[i], fullWidth - 2, widths[i] - 2);
        return Qt.rect(starts[i], side === "bottom" ? 2 : 0, widths[i] - 4, fullHeight - 2);
    }

    function along(m) {
        return vertical ? m.y : m.x;
    }

    function tabAt(at) {
        for (var i = 0; i < tabs.length; i++) if (at >= starts[i] && at <= starts[i] + widths[i]) return i;
        return -1;
    }

    function slotAt(at) {
        if (!tabs.length) return 0;
        if (at >= starts[tabs.length - 1] + widths[tabs.length - 1]) return tabs.length - 1;
        for (var i = 0; i < tabs.length; i++) if (at < starts[i] + widths[i]) return i;
        return 0;
    }

    function tabTitled(i) {
        return vertical ? titled : !compact || tabs[i].active;
    }

    function showsButtons(i) {
        if (i < 0 || i >= tabs.length || tabs[i].minimized || (i !== activeIndex && i !== mouse.hoveredIndex)) return false;
        return tabTitled(i) && tabRect(i).width >= buttonsWidth + iconWidth - 4;
    }

    function collapse() {
        if (!mouse.containsMouse && !mouse.pressedId) expanded = false;
    }

    function buttonLeft(width, b) {
        return width - buttonInset - buttonStep * 2 - buttonSize + b * buttonStep;
    }

    function buttonAt(x, y) {
        var shown = [activeIndex, mouse.hoveredIndex].filter(showsButtons);
        for (var n = 0; n < shown.length; n++) {
            var r = tabRect(shown[n]);
            var top = r.y + Math.round((r.height - buttonSize) / 2);
            for (var b = 0; b < 3; b++) {
                var left = r.x + buttonLeft(r.width, b);
                if (x >= left - 1 && x <= left + buttonSize + 1 && y >= top - 1 && y <= top + buttonSize + 1) return tabs[shown[n]].id + "|" + buttonNames[b];
            }
        }
        return "";
    }

    Timer {
        id: openTimer
        interval: 150
        onTriggered: bar.expanded = true
    }

    Item {
        id: content
        x: bar.vertical ? 0 : -bar.offset
        y: bar.vertical ? -bar.offset : 0
        width: bar.fullWidth
        height: bar.fullHeight

        Text {
            x: 0
            y: !bar.vertical && bar.side === "bottom" ? 2 : 0
            width: bar.vertical ? bar.fullWidth : bar.labelWidth
            height: bar.vertical ? bar.rowHeight : bar.fullHeight - 2
            text: bar.label
            color: "#8c9ec2"
            font.weight: Font.DemiBold
            font.pixelSize: 12
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        Repeater {
            model: bar.tabs.length
            Item {
                readonly property var tab: bar.tabs[index]
                readonly property var area: bar.tabRect(index)
                readonly property bool trailing: bar.showsButtons(index)
                readonly property bool titled: bar.tabTitled(index)
                x: area.x || 0
                y: area.y || 0
                width: Math.max(0, area.width || 0)
                height: Math.max(0, area.height || 0)
                clip: true
                Rectangle {
                    x: bar.side === "left" ? -4 : 0
                    y: bar.side === "top" ? -4 : 0
                    width: parent.width + (bar.vertical ? 4 : 0)
                    height: parent.height + (bar.vertical ? 0 : 4)
                    radius: 4
                    color: tab.active ? "#386bd1" : "#24334f"
                }
                Kirigami.Icon {
                    x: parent.titled ? 4 : Math.round((parent.width - width) / 2)
                    width: 16
                    height: 16
                    anchors.verticalCenter: parent.verticalCenter
                    source: tab.icon
                    opacity: tab.minimized ? 0.4 : 1
                }
                Text {
                    visible: parent.titled
                    x: 24
                    width: Math.max(0, parent.width - (parent.trailing ? bar.buttonsWidth : 0) - 26)
                    height: parent.height
                    text: tab.title
                    color: tab.minimized ? "#8c8c8c" : "#ebebeb"
                    font.pixelSize: 12
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                }
                Repeater {
                    model: parent.trailing ? 3 : 0
                    Rectangle {
                        readonly property string name: bar.buttonNames[index]
                        readonly property string key: tab.id + "|" + name
                        readonly property bool closing: name === "close"
                        readonly property bool lit: mouse.hoveredButton === key || mouse.pressedButton === key
                        x: bar.buttonLeft(parent.width, index)
                        y: Math.round((parent.height - bar.buttonSize) / 2)
                        width: bar.buttonSize
                        height: bar.buttonSize
                        radius: width / 2
                        color: !lit ? "transparent" : closing ? (mouse.pressedButton === key ? "#b83241" : "#da4453")
                            : mouse.pressedButton === key ? "#4dffffff" : "#26ffffff"
                        Kirigami.Icon {
                            anchors.centerIn: parent
                            width: 16
                            height: 16
                            source: parent.name === "minimize" ? "window-minimize"
                                : parent.name === "close" ? "window-close"
                                : tab.filled ? "window-restore" : "window-maximize"
                            isMask: true
                            color: parent.closing && parent.lit ? "#ffffff" : "#ebebeb"
                        }
                    }
                }
            }
        }

        Rectangle {
            visible: bar.leftLine
            width: 1
            height: bar.fullHeight
            color: "#6b6b6b"
        }

        Rectangle {
            visible: bar.topLine
            width: bar.fullWidth
            height: 1
            color: "#6b6b6b"
        }

        MouseArea {
            id: mouse

            property string pressedId
            property string pressedButton
            property point start
            property bool dragging
            property string hoveredButton
            property int hoveredIndex: -1
            property point pointer

            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            hoverEnabled: true

            function inside(m) {
                return m.x + content.x >= 0 && m.y + content.y >= 0 && m.x + content.x < bar.width && m.y + content.y < bar.height;
            }

            function track() {
                var at = bar.along(pointer);
                hoveredIndex = containsMouse && !pressedId && at >= bar.labelExtent ? bar.tabAt(at) : -1;
                hoveredButton = hoveredIndex >= 0 ? bar.buttonAt(pointer.x, pointer.y) : "";
            }

            onEntered: if (bar.expandable && !bar.expanded) openTimer.start()
            onPositionChanged: (m) => {
                pointer = Qt.point(m.x, m.y);
                track();
                if (!pressedId) return;
                if (!dragging && Math.hypot(m.x - start.x, m.y - start.y) < 4) return;
                dragging = true;
                if (inside(m)) bar.reorder(pressedId, bar.slotAt(bar.along(m)));
                else bar.carry(pressedId);
            }
            onExited: {
                hoveredButton = "";
                hoveredIndex = -1;
                openTimer.stop();
                Qt.callLater(bar.collapse);
            }
            onPressed: (m) => {
                dragging = false;
                pressedId = "";
                var at = bar.along(m);
                if (m.button === Qt.RightButton) {
                    var right = bar.tabAt(at);
                    if (at >= bar.labelExtent && right >= 0) bar.tabMenu(bar.tabs[right].id);
                    else bar.labelMenu();
                    return;
                }
                var hit = bar.buttonAt(m.x, m.y);
                if (hit) {
                    pressedButton = hit;
                    return;
                }
                if (at < bar.labelExtent) {
                    bar.labelClicked();
                    return;
                }
                var index = bar.tabAt(at);
                if (index < 0) return;
                pressedId = bar.tabs[index].id;
                start = Qt.point(m.x, m.y);
            }
            onReleased: (m) => {
                if (pressedButton) {
                    var hit = bar.buttonAt(m.x, m.y);
                    var parts = pressedButton.split("|");
                    if (hit === pressedButton) bar.press(parts[0], parts[1]);
                    pressedButton = "";
                    return;
                }
                if (!pressedId) return;
                var id = pressedId;
                pressedId = "";
                if (!dragging) bar.select(id);
                else if (!inside(m)) bar.drop(id);
                else bar.reorder(id, bar.slotAt(bar.along(m)));
                dragging = false;
                Qt.callLater(bar.collapse);
                track();
            }
        }
    }
}
