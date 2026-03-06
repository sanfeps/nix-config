import QtQuick
import QtQuick.Layouts
import ".." as Root

Rectangle {
    id: root
    implicitWidth: 280
    implicitHeight: col.implicitHeight + Root.Theme.spacingLg * 2
    color: "transparent"

    Column {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: Root.Theme.spacingLg }
        spacing: Root.Theme.spacingMd

        // Header + power toggle
        RowLayout {
            anchors { left: parent.left; right: parent.right; leftMargin: Root.Theme.spacingMd; rightMargin: Root.Theme.spacingMd }

            Text {
                text: "Bluetooth"
                font.family:    Root.Theme.fontFamilyAlt
                font.pixelSize: Root.Theme.fontSizeLg
                font.weight:    Font.Medium
                color: Root.Colors.onSurface
                Layout.fillWidth: true
            }

            // Power toggle
            Rectangle {
                width:  44
                height: 24
                radius: Root.Theme.radiusFull
                color:  Root.BluetoothService.powered ? Root.Colors.primary : Root.Colors.surfaceVariant
                Behavior on color { ColorAnimation { duration: Root.Theme.animFast } }

                Rectangle {
                    width:  18
                    height: 18
                    radius: Root.Theme.radiusFull
                    color:  Root.BluetoothService.powered ? Root.Colors.onPrimary : Root.Colors.onSurfaceVariant
                    anchors.verticalCenter: parent.verticalCenter
                    x: Root.BluetoothService.powered ? parent.width - width - 3 : 3
                    Behavior on x { NumberAnimation { duration: Root.Theme.animFast; easing.type: Easing.OutCubic } }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: Root.BluetoothService.togglePower()
                    cursorShape: Qt.PointingHandCursor
                }
            }
        }

        // Device info
        RowLayout {
            visible: Root.BluetoothService.connected
            anchors { left: parent.left; right: parent.right; leftMargin: Root.Theme.spacingMd; rightMargin: Root.Theme.spacingMd }
            spacing: Root.Theme.spacingMd

            Text {
                text: "bluetooth_connected"
                font.family:    "Material Symbols Rounded"
                font.pixelSize: Root.Theme.iconMd
                color: Root.Colors.primary
            }

            Text {
                text: Root.BluetoothService.deviceName || "Connected device"
                font.family:    Root.Theme.fontFamily
                font.pixelSize: Root.Theme.fontSizeMd
                color: Root.Colors.onSurface
            }
        }
    }
}
