import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import "../.."

RowLayout {
    id: workspaces
    spacing: 6

    Repeater {
        model: 9  // Show workspaces 1-9

        Rectangle {
            required property int index
            property int workspaceId: index + 1

            property bool isActive: Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.name === workspaceId.toString()
            property bool hasWindows: {
                if (!Hyprland.workspaces) return false
                var workspacesList = Hyprland.workspaces.values
                for (var i = 0; i < workspacesList.length; i++) {
                    var ws = workspacesList[i]
                    if (ws.name === workspaceId.toString() && ws.windows && ws.windows.length > 0) {
                        return true
                    }
                }
                return false
            }

            implicitWidth: 24
            implicitHeight: 24
            Layout.alignment: Qt.AlignVCenter

            radius: 4
            color: isActive ? "#89b4fa" : (hasWindows ? "#45475a" : "transparent")
            border.width: !isActive ? 1 : 0
            border.color: hasWindows ? "#6c7086" : "#313244"

            Behavior on color {
                ColorAnimation { duration: 150 }
            }

            Text {
                anchors.centerIn: parent
                text: workspaceId
                color: isActive ? "#1e1e2e" : "#cdd6f4"
                font.pixelSize: 11
                font.weight: isActive ? Font.Bold : Font.Normal
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor

                onEntered: parent.opacity = 0.8
                onExited: parent.opacity = 1.0

                onClicked: {
                    // Use name: prefix since workspaces are named
                    Hyprland.dispatch("workspace name:" + workspaceId.toString())
                }
            }
        }
    }
}
