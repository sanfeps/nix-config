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
            ? Qt.rgba(Root.Colors.surfaceFg.r, Root.Colors.surfaceFg.g, Root.Colors.surfaceFg.b, Root.Theme.opacityHover)
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
                    ? Root.Colors.surfaceFg
                    : Root.Colors.surfaceFgVariant
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
