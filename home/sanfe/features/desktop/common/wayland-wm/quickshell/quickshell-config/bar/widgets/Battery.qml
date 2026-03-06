import QtQuick
import QtQuick.Layouts
import "../../.." as Root

Item {
    id: root
    implicitHeight: Root.Theme.barHeight
    implicitWidth: visible ? row.width + Root.Theme.spacingMd * 2 : 0
    visible: Root.BatteryService.present

    Rectangle {
        anchors.fill: parent
        radius: Root.Theme.radiusMd
        color: "transparent"

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: Root.Theme.spacingXs

            Text {
                text: Root.BatteryService.icon()
                font.family:    "Material Symbols Rounded"
                font.pixelSize: Root.Theme.iconMd
                color: {
                    if (Root.BatteryService.charging) return Root.Colors.tertiary
                    if (Root.BatteryService.capacity <= 15) return Root.Colors.error
                    if (Root.BatteryService.capacity <= 30) return Root.Colors.secondary
                    return Root.Colors.surfaceFg
                }
            }

            Text {
                text: Root.BatteryService.capacity + "%"
                font.family:    Root.Theme.fontFamily
                font.pixelSize: Root.Theme.fontSizeSm
                color: Root.Colors.surfaceFgVariant
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
        }
    }
}
