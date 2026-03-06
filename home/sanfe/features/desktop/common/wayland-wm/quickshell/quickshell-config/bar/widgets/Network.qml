import QtQuick
import QtQuick.Layouts
import "../../.." as Root

Item {
    id: root
    implicitHeight: Root.Theme.barHeight
    implicitWidth: row.width + Root.Theme.spacingMd * 2

    Rectangle {
        anchors.fill: parent
        radius: Root.Theme.radiusMd
        color: hoverArea.containsMouse
            ? Qt.rgba(Root.Colors.surfaceFg.r, Root.Colors.surfaceFg.g, Root.Colors.surfaceFg.b, Root.Theme.opacityHover)
            : "transparent"
        Behavior on color { ColorAnimation { duration: Root.Theme.animFast } }

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: Root.Theme.spacingXs

            Text {
                text: Root.NetworkService.icon()
                font.family:    "Material Symbols Rounded"
                font.pixelSize: Root.Theme.iconMd
                color: Root.NetworkService.connected ? Root.Colors.surfaceFg : Root.Colors.surfaceFgVariant
            }

            Text {
                text: {
                    var s = Root.NetworkService.ssid
                    return s.length > 14 ? s.substring(0, 14) + "…" : s
                }
                font.family:    Root.Theme.fontFamily
                font.pixelSize: Root.Theme.fontSizeSm
                color: Root.Colors.surfaceFgVariant
                visible: Root.NetworkService.connected && Root.NetworkService.ssid !== ""
            }
        }

        MouseArea {
            id: hoverArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
        }
    }
}
