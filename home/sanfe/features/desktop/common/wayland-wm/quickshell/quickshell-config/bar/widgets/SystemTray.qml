import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../.." as Root

Item {
    id: root
    implicitWidth: trayRow.width
    implicitHeight: Root.Globals.barHeight - 12

    Row {
        id: trayRow
        spacing: Root.Globals.spacing
        anchors.centerIn: parent

        // Placeholder for system tray items
        // Quickshell's system tray support varies by version
        // This is a basic structure that can be expanded

        Repeater {
            model: 0 // Will be populated when system tray items are available

            Rectangle {
                width: 24
                height: 24
                radius: Root.Globals.radiusSmall
                color: Qt.rgba(Root.Globals.backgroundAlt.r, Root.Globals.backgroundAlt.g, Root.Globals.backgroundAlt.b, 0.5)

                Text {
                    anchors.centerIn: parent
                    text: "?"
                    color: Root.Globals.textColor
                    font.pixelSize: Root.Globals.fontNormal
                }
            }
        }
    }
}
