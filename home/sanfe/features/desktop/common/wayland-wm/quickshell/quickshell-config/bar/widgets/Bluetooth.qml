import QtQuick
import "../../.." as Root

Item {
    id: root
    implicitHeight: Root.Theme.barHeight
    implicitWidth: Root.Theme.iconMd + Root.Theme.spacingMd * 2

    Rectangle {
        anchors.fill: parent
        radius: Root.Theme.radiusMd
        color: hoverArea.containsMouse
            ? Qt.rgba(Root.Colors.onSurface.r, Root.Colors.onSurface.g, Root.Colors.onSurface.b, Root.Theme.opacityHover)
            : "transparent"
        Behavior on color { ColorAnimation { duration: Root.Theme.animFast } }

        Text {
            anchors.centerIn: parent
            text: Root.BluetoothService.icon()
            font.family:    "Material Symbols Rounded"
            font.pixelSize: Root.Theme.iconMd
            color: Root.BluetoothService.connected
                ? Root.Colors.primary
                : Root.BluetoothService.powered
                    ? Root.Colors.onSurface
                    : Root.Colors.onSurfaceVariant
        }

        MouseArea {
            id: hoverArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Root.BluetoothService.togglePower()
        }
    }
}
