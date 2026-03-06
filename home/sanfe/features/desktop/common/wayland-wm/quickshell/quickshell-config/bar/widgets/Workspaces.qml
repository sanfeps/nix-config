import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../.." as Root

Item {
    id: root
    implicitWidth: row.width + Root.Theme.spacingMd * 2
    implicitHeight: Root.Theme.barHeight

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 5

        Repeater {
            model: 9

            Item {
                id: wsItem
                required property int index
                property int wsId: index + 1

                property bool isActive: Root.CompositorService.activeWorkspace === wsId
                property bool hasWindows: {
                    var wsList = Root.CompositorService.workspaces
                    for (var i = 0; i < wsList.length; i++) {
                        if (wsList[i].id === wsId && wsList[i].windows > 0)
                            return true
                    }
                    return false
                }

                width:  isActive ? 28 : (hasWindows ? 10 : 6)
                height: 6

                Behavior on width {
                    NumberAnimation { duration: Root.Theme.animFast; easing.type: Easing.OutCubic }
                }

                Rectangle {
                    anchors.fill: parent
                    radius: Root.Theme.radiusFull

                    color: wsItem.isActive
                        ? Root.Colors.primary
                        : wsItem.hasWindows
                            ? Root.Colors.surfaceVariant
                            : "transparent"

                    border.width: (!wsItem.isActive && !wsItem.hasWindows) ? 1 : 0
                    border.color: Root.Colors.outline

                    Behavior on color {
                        ColorAnimation { duration: Root.Theme.animFast }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked:   Root.CompositorService.switchWorkspace(wsItem.wsId)
                }
            }
        }
    }
}
