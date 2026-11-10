import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.workspace.dbus as DBus

PlasmoidItem {
    Plasmoid.status: PlasmaCore.Types.ActiveStatus
    Plasmoid.icon: "local.screenzones"
    activationTogglesExpanded: false
    toolTipMainText: "ScreenZones"
    fullRepresentation: Item {}

    compactRepresentation: MouseArea {
        onClicked: DBus.SessionBus.asyncCall({
            service: "org.kde.kglobalaccel",
            path: "/component/kwin",
            iface: "org.kde.kglobalaccel.Component",
            member: "invokeShortcut",
            arguments: [new DBus.string("ScreenZones Menu")]
        })

        Kirigami.Icon {
            anchors.fill: parent
            source: Qt.resolvedUrl("../images/tray.svg")
        }
    }
}
