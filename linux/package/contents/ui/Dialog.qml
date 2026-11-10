import QtQuick
import QtQuick.Window as QW
import QtQuick.Controls as QQC

QW.Window {
    id: dialog

    property string heading
    property string message
    property string text
    property bool asksText: true
    property string acceptLabel
    property bool finished

    signal accepted(string text)

    title: "ScreenZones dialog"
    flags: Qt.Popup | Qt.FramelessWindowHint
    width: 360
    height: content.implicitHeight + 32
    color: "#2e2e2e"

    function finish(accept) {
        if (finished) return;
        finished = true;
        var value = field.text.trim();
        visible = false;
        if (accept) accepted(asksText ? value || text : value);
        destroy();
    }

    onVisibleChanged: if (!visible) finish(false)

    Column {
        id: content
        x: 16
        y: 16
        width: parent.width - 32
        spacing: 12
        Keys.onEscapePressed: dialog.finish(false)

        Text {
            width: parent.width
            text: dialog.heading
            color: "white"
            font.pixelSize: 14
            font.weight: Font.DemiBold
            wrapMode: Text.Wrap
        }
        Text {
            visible: dialog.message !== ""
            width: parent.width
            text: dialog.message
            color: "#cccccc"
            font.pixelSize: 12
            wrapMode: Text.Wrap
        }
        QQC.TextField {
            id: field
            visible: dialog.asksText
            width: parent.width
            text: dialog.text
            focus: dialog.asksText
            Component.onCompleted: selectAll()
            onAccepted: dialog.finish(true)
        }
        Row {
            anchors.right: parent.right
            spacing: 8
            focus: !dialog.asksText
            Keys.onReturnPressed: dialog.finish(true)
            Keys.onEnterPressed: dialog.finish(true)
            QQC.Button {
                text: "Cancelar"
                onClicked: dialog.finish(false)
            }
            QQC.Button {
                text: dialog.acceptLabel
                highlighted: true
                onClicked: dialog.finish(true)
            }
        }
    }
}
