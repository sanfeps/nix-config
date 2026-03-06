import QtQuick
import QtQuick.Layouts
import "../../.." as Root

Item {
    id: root
    implicitHeight: Root.Theme.barHeight
    implicitWidth: visible ? row.width + Root.Theme.spacingMd * 2 : 0
    visible: Root.MediaService.hasPlayer

    Rectangle {
        anchors.fill: parent
        radius: Root.Theme.radiusMd
        color: mediaHover.containsMouse
            ? Qt.rgba(Root.Colors.onSurface.r, Root.Colors.onSurface.g, Root.Colors.onSurface.b, Root.Theme.opacityHover)
            : "transparent"
        Behavior on color { ColorAnimation { duration: Root.Theme.animFast } }

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: Root.Theme.spacingSm

            // Prev
            Text {
                text: "skip_previous"
                font.family:    "Material Symbols Rounded"
                font.pixelSize: Root.Theme.iconSm
                color: Root.Colors.onSurfaceVariant
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Root.MediaService.previous()
                }
            }

            // Play/pause
            Text {
                text: Root.MediaService.playing ? "pause" : "play_arrow"
                font.family:    "Material Symbols Rounded"
                font.pixelSize: Root.Theme.iconMd
                color: Root.Colors.primary
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Root.MediaService.playPause()
                }
            }

            // Next
            Text {
                text: "skip_next"
                font.family:    "Material Symbols Rounded"
                font.pixelSize: Root.Theme.iconSm
                color: Root.Colors.onSurfaceVariant
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Root.MediaService.next()
                }
            }

            // Track info (max 24 chars)
            Text {
                text: {
                    var t = Root.MediaService.trackTitle
                    return t.length > 22 ? t.substring(0, 22) + "…" : t
                }
                font.family:    Root.Theme.fontFamily
                font.pixelSize: Root.Theme.fontSizeSm
                color: Root.Colors.onSurface
                visible: text !== ""
            }
        }

        MouseArea {
            id: mediaHover
            anchors.fill: parent
            hoverEnabled: true
            propagateComposedEvents: true
            onClicked: mouse => mouse.accepted = false
        }
    }
}
