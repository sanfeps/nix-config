import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import "../.." as Root

Item {
    id: root
    implicitWidth: workspaceBox.width
    implicitHeight: 24

    Rectangle {
        id: workspaceBox
        width: workspaceRow.width + 16
        height: 24
        anchors.verticalCenter: parent.verticalCenter
        color: Qt.rgba(Root.Globals.backgroundAlt.r, Root.Globals.backgroundAlt.g, Root.Globals.backgroundAlt.b, 0.6)
        radius: Root.Globals.radiusLarge

        Row {
            id: workspaceRow
            anchors.centerIn: parent
            spacing: 8

            Repeater {
                model: 9

                Rectangle {
                    id: workspaceIndicator
                    required property int index
                    property int workspaceId: index + 1

                    property bool isActive: {
                        if (!Hyprland.focusedWorkspace) return false
                        return Hyprland.focusedWorkspace.name === workspaceId.toString()
                    }

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

                    width: isActive ? 36 : (hasWindows ? 12 : 8)
                    height: 6
                    radius: 3

                    color: {
                        if (isActive) return Root.Globals.accentColor
                        if (hasWindows) return Root.Globals.surfaceColor
                        return "transparent"
                    }

                    border.width: !isActive && !hasWindows ? 1 : 0
                    border.color: Root.Globals.overlayColor

                    Behavior on width {
                        NumberAnimation {
                            duration: Root.Globals.animationDuration
                            easing.type: Easing.OutCubic
                        }
                    }

                    Behavior on color {
                        ColorAnimation { duration: Root.Globals.animationDuration }
                    }

                    // No text - just indicator bars like thorn

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor

                        onClicked: {
                            Hyprland.dispatch("workspace name:" + workspaceId.toString())
                        }
                    }
                }
            }
        }
    }
}
