import QtQuick
import QtQuick.Window as QW

QW.Window {
    id: badge

    property var lines: []
    property bool outputOnly: true

    title: "ScreenZones badge"
    flags: Qt.FramelessWindowHint | Qt.WindowDoesNotAcceptFocus
    color: "transparent"

    function measure() {
        labels.forceLayout();
        values.forceLayout();
        table.forceLayout();
        return { width: Math.ceil(table.implicitWidth) + 24, height: Math.ceil(table.implicitHeight) + 16 };
    }

    Rectangle {
        anchors.fill: parent
        radius: 6
        color: "#f0141724"
        border.color: "#5c5c66"
        Row {
            id: table
            x: 12
            y: 8
            spacing: 14
            Column {
                id: labels
                spacing: 2
                Repeater {
                    model: badge.lines
                    Text {
                        text: modelData.label
                        color: "#9eb3d9"
                        font.pixelSize: 13
                        font.features: { "tnum": 1 }
                    }
                }
            }
            Column {
                id: values
                spacing: 2
                Repeater {
                    model: badge.lines
                    Text {
                        anchors.right: parent.right
                        text: modelData.value
                        color: "#ededed"
                        font.pixelSize: 13
                        font.features: { "tnum": 1 }
                    }
                }
            }
        }
    }
}
