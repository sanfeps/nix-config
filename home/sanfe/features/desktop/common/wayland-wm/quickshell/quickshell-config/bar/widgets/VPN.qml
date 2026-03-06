import QtQuick
import "../../.." as Root

Item {
    id: root
    implicitHeight: Root.Theme.barHeight
    implicitWidth: Root.Theme.iconMd + Root.Theme.spacingMd * 2

    Text {
        anchors.centerIn: parent
        text: "vpn_lock"
        font.family:    "Material Symbols Rounded"
        font.pixelSize: Root.Theme.iconMd
        color: Root.VpnService.active ? Root.Colors.tertiary : Root.Colors.onSurfaceVariant
        opacity: Root.VpnService.active ? 1.0 : 0.5

        Behavior on color   { ColorAnimation  { duration: Root.Theme.animNormal } }
        Behavior on opacity { NumberAnimation { duration: Root.Theme.animNormal } }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
    }
}
