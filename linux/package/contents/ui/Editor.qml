import QtQuick
import QtQuick.Window as QW
import org.kde.kirigami as Kirigami
import "../code/geometry.js" as Geometry

QW.Window {
    id: editor

    property string heading
    property var zones: []
    property real panelScale: 1
    property bool finished

    signal saved(var zones)
    signal closed()

    readonly property var actions: [
        { name: "columns", icon: "view-split-left-right" },
        { name: "rows", icon: "view-split-top-bottom" },
        { name: "remove", icon: "edit-delete-remove" }
    ]
    readonly property int buttonWidth: 44
    readonly property int buttonHeight: 32
    readonly property int spacing: 8
    readonly property int grip: 16
    readonly property rect bounds: Qt.rect(0, 0, width, height)

    title: "ScreenZones editor"
    flags: Qt.Popup | Qt.FramelessWindowHint
    color: "#99000000"

    function result(action, index) {
        if (action === "columns") return Geometry.splitting(zones, index, "x");
        if (action === "rows") return Geometry.splitting(zones, index, "y");
        return Geometry.removing(zones, index);
    }

    function finish(save) {
        if (finished) return;
        finished = true;
        if (save) saved(zones);
        closed();
    }

    function divider(x, y) {
        var placed = zones.map(function (z) { return Geometry.place(z, bounds, "top", 0); });
        var lines = Geometry.dividers(placed, bounds, 0);
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i];
            if (x < line.x - grip / 2 || x > line.x + line.width + grip / 2 || y < line.y - grip / 2 || y > line.y + line.height + grip / 2) continue;
            var axis = line.width < line.height ? "x" : "y";
            var value = axis === "x" ? (line.x + line.width / 2) / width : (line.y + line.height / 2) / height;
            var edges = [];
            zones.forEach(function (z) { edges = edges.concat(axis === "x" ? [z.x, z.x + z.w] : [z.y, z.y + z.h]); });
            var from = edges.reduce(function (a, b) { return Math.abs(b - value) < Math.abs(a - value) ? b : a; });
            return { axis: axis, from: from };
        }
        return null;
    }

    function size(r) {
        return Math.round(r.width) + " × " + Math.round(r.height) + " px";
    }

    onVisibleChanged: if (!visible) finish(false)

    Item {
        id: canvas
        anchors.fill: parent
        focus: true
        Keys.onReturnPressed: editor.finish(true)
        Keys.onEnterPressed: editor.finish(true)
        Keys.onEscapePressed: editor.finish(false)

        Repeater {
            model: editor.zones.length
            Item {
                id: cell
                readonly property int zoneIndex: index
                readonly property var zone: editor.zones[index]
                readonly property var placed: Geometry.place(zone, editor.bounds, "top", 0)
                x: zone.x * editor.width + 4
                y: zone.y * editor.height + 4
                width: zone.w * editor.width - 8
                height: zone.h * editor.height - 8

                Rectangle {
                    anchors.fill: parent
                    radius: 8
                    color: "#33386bd1"
                    border.color: "#386bd1"
                    border.width: 2
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: parent.height / 2 - 44 - height / 2
                    text: cell.zone.id
                    color: "#f2ffffff"
                    font.pixelSize: 44
                    font.weight: Font.DemiBold
                }
                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: parent.height / 2 - 16
                    Repeater {
                        model: [
                            "Zona: " + editor.size(cell.placed.full) + "  ·  " + Math.round(cell.zone.w * 100) + " % × " + Math.round(cell.zone.h * 100) + " %",
                            "Físicos: " + editor.size(Qt.rect(0, 0, cell.placed.full.width * editor.panelScale, cell.placed.full.height * editor.panelScale))
                        ]
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: modelData
                            color: "#cccccc"
                            font.pixelSize: 12
                        }
                    }
                }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: parent.height / 2 + 38
                    spacing: editor.spacing
                    Repeater {
                        model: editor.actions
                        Rectangle {
                            readonly property bool available: editor.result(modelData.name, cell.zoneIndex) !== null
                            width: editor.buttonWidth
                            height: editor.buttonHeight
                            radius: 6
                            color: available && hover.containsMouse ? "#525252" : "#2e2e2e"
                            Kirigami.Icon {
                                anchors.centerIn: parent
                                width: 18
                                height: 18
                                source: modelData.icon
                                color: "white"
                                isMask: true
                                opacity: parent.available ? 1 : 0.3
                            }
                            MouseArea {
                                id: hover
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    var next = editor.result(modelData.name, cell.zoneIndex);
                                    if (next) editor.zones = next;
                                }
                            }
                        }
                    }
                }
            }
        }

        MouseArea {
            id: lines
            property var drag: null
            anchors.fill: parent
            z: -1
            hoverEnabled: true
            cursorShape: {
                var line = editor.divider(mouseX, mouseY);
                return drag ? (drag.axis === "x" ? Qt.SizeHorCursor : Qt.SizeVerCursor)
                    : line ? (line.axis === "x" ? Qt.SizeHorCursor : Qt.SizeVerCursor) : Qt.ArrowCursor;
            }
            onPressed: (m) => drag = editor.divider(m.x, m.y)
            onPositionChanged: (m) => {
                if (!drag) return;
                var to = drag.axis === "x" ? m.x / editor.width : m.y / editor.height;
                if (Math.abs(to - drag.from) <= 0.0001) return;
                var next = Geometry.moving(editor.zones, { axis: drag.axis, from: drag.from, to: to });
                if (!next) return;
                editor.zones = next;
                drag = { axis: drag.axis, from: Math.round(to * 10000) / 10000 };
            }
            onReleased: drag = null
        }

        Rectangle {
            id: toolbar
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height - 76
            width: help.implicitWidth + 16 + 24 + 96 * 2 + 8 + 12
            height: 48
            radius: 10
            color: "#2e2e2e"
            Text {
                id: help
                x: 16
                anchors.verticalCenter: parent.verticalCenter
                text: editor.heading + " · Arrastra las líneas para cambiar los tamaños"
                color: "#cccccc"
                font.pixelSize: 12
            }
            Row {
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                Repeater {
                    model: [{ text: "Cancelar", save: false, color: "#525252" }, { text: "Guardar", save: true, color: "#386bd1" }]
                    Rectangle {
                        width: 96
                        height: 28
                        radius: 6
                        color: modelData.color
                        Text {
                            anchors.centerIn: parent
                            text: modelData.text
                            color: "white"
                            font.pixelSize: 13
                            font.weight: Font.Medium
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: editor.finish(modelData.save)
                        }
                    }
                }
            }
        }
    }
}
