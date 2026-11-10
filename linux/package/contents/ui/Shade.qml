import QtQuick
import QtQuick.Window as QW

QW.Window {
    property bool outputOnly: true
    property alias fill: area.color
    property alias border: area.border
    property alias radius: area.radius

    title: "ScreenZones shade"
    flags: Qt.FramelessWindowHint | Qt.WindowDoesNotAcceptFocus
    color: "transparent"

    Rectangle {
        id: area
        anchors.fill: parent
    }
}
