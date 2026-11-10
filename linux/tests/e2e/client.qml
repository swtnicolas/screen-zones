import QtQuick

Window {
    readonly property var args: Qt.application.arguments
    readonly property int base: args.indexOf("--") + 1
    title: args[base] || "client"
    width: Number(args[base + 1] || 400)
    height: Number(args[base + 2] || 300)
    minimumWidth: Number(args[base + 3] || 0)
    minimumHeight: Number(args[base + 4] || 0)
    readonly property bool closesWhenInactive: args[base + 6] === "closes"
    color: "#335"
    visible: false
    onWidthChanged: print("width " + width)
    onHeightChanged: print("height " + height)
    onActiveChanged: if (closesWhenInactive && !active) close()

    MouseArea {
        anchors.fill: parent
        onClicked: (m) => print("clicked " + Math.round(m.x) + " " + Math.round(m.y))
    }

    Component.onCompleted: {
        if (args[base + 5]) Qt.application.domain = args[base + 5];
        visible = true;
    }
}
