import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import ".." as Root

Rectangle {
    id: root
    implicitWidth: 280
    implicitHeight: col.implicitHeight + Root.Theme.spacingLg * 2
    color: "transparent"

    Column {
        id: col
        anchors {
            left:   parent.left
            right:  parent.right
            top:    parent.top
            topMargin: Root.Theme.spacingLg
        }
        spacing: Root.Theme.spacingMd

        // Header
        Text {
            text: "Audio"
            font.family:    Root.Theme.fontFamilyAlt
            font.pixelSize: Root.Theme.fontSizeLg
            font.weight:    Font.Medium
            color: Root.Colors.onSurface
            leftPadding: Root.Theme.spacingMd
        }

        // Volume slider row
        RowLayout {
            anchors { left: parent.left; right: parent.right }
            anchors.leftMargin:  Root.Theme.spacingMd
            anchors.rightMargin: Root.Theme.spacingMd
            spacing: Root.Theme.spacingMd

            Text {
                text: Root.AudioService.volumeIcon()
                font.family:    "Material Symbols Rounded"
                font.pixelSize: Root.Theme.iconLg
                color: Root.AudioService.muted ? Root.Colors.error : Root.Colors.primary
                MouseArea {
                    anchors.fill: parent
                    onClicked: Root.AudioService.toggleMute()
                    cursorShape: Qt.PointingHandCursor
                }
            }

            // Simple slider
            Rectangle {
                id: sliderTrack
                Layout.fillWidth: true
                height: 4
                radius: Root.Theme.radiusFull
                color: Root.Colors.surfaceVariant

                Rectangle {
                    width: parent.width * (Root.AudioService.muted ? 0 : Root.AudioService.volume)
                    height: parent.height
                    radius: parent.radius
                    color: Root.Colors.primary
                    Behavior on width { NumberAnimation { duration: Root.Theme.animFast } }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: mouse => {
                        var pct = mouse.x / width
                        Root.AudioService.setVolume(pct)
                    }
                    cursorShape: Qt.SizeHorCursor
                }
            }

            Text {
                text: Math.round(Root.AudioService.volume * 100) + "%"
                font.family:    Root.Theme.fontFamily
                font.pixelSize: Root.Theme.fontSizeSm
                color: Root.Colors.onSurfaceVariant
                Layout.minimumWidth: 36
            }
        }
    }
}
