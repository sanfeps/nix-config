import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import "../.." as Root

Item {
    id: root
    implicitHeight: 24
    Layout.fillWidth: true

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 0
        anchors.bottomMargin: 0
        color: Qt.rgba(Root.Globals.backgroundAlt.r, Root.Globals.backgroundAlt.g, Root.Globals.backgroundAlt.b, 0.4)
        radius: Root.Globals.radiusLarge

        RowLayout {
            anchors.fill: parent
            anchors.margins: Root.Globals.padding
            spacing: Root.Globals.spacing

            Text {
                id: windowIcon
                text: ""
                font.family: "Material Symbols Rounded"
                font.pixelSize: Root.Globals.fontLarge
                color: Root.Globals.accentColor
                visible: Hyprland.focusedWindow !== null
            }

            Text {
                id: windowTitle
                Layout.fillWidth: true
                text: {
                    if (!Hyprland.focusedWindow) return "Desktop"
                    var title = Hyprland.focusedWindow.title
                    return title || Hyprland.focusedWindow.class || "Window"
                }
                color: Root.Globals.textColor
                font.family: Root.Globals.font
                font.pixelSize: Root.Globals.fontNormal
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }
        }
    }
}
