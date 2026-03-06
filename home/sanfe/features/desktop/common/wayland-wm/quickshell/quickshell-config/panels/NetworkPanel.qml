import QtQuick
import QtQuick.Layouts
import ".." as Root

Rectangle {
    id: root
    implicitWidth: 300
    implicitHeight: col.implicitHeight + Root.Theme.spacingLg * 2
    color: "transparent"

    Column {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: Root.Theme.spacingLg }
        spacing: Root.Theme.spacingMd

        Text {
            text: "Network"
            font.family:    Root.Theme.fontFamilyAlt
            font.pixelSize: Root.Theme.fontSizeLg
            font.weight:    Font.Medium
            color: Root.Colors.onSurface
            leftPadding: Root.Theme.spacingMd
        }

        // Status row
        RowLayout {
            anchors { left: parent.left; right: parent.right; leftMargin: Root.Theme.spacingMd; rightMargin: Root.Theme.spacingMd }
            spacing: Root.Theme.spacingMd

            Text {
                text: Root.NetworkService.icon()
                font.family:    "Material Symbols Rounded"
                font.pixelSize: Root.Theme.iconLg
                color: Root.NetworkService.connected ? Root.Colors.primary : Root.Colors.onSurfaceVariant
            }

            Column {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    text: Root.NetworkService.connected ? (Root.NetworkService.ssid || "Connected") : "Disconnected"
                    font.family:    Root.Theme.fontFamily
                    font.pixelSize: Root.Theme.fontSizeMd
                    color: Root.Colors.onSurface
                }

                Text {
                    visible: Root.NetworkService.type === "wifi"
                    text: "Signal: " + Root.NetworkService.strength + "%"
                    font.family:    Root.Theme.fontFamily
                    font.pixelSize: Root.Theme.fontSizeXs
                    color: Root.Colors.onSurfaceVariant
                }
            }
        }
    }
}
