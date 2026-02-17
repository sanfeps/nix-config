import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris
import "../.." as Root

Item {
    id: root
    implicitWidth: mediaBox.width
    implicitHeight: 24
    visible: Mpris.players.values.length > 0

    property var player: Mpris.players.values.length > 0 ? Mpris.players.values[0] : null

    Rectangle {
        id: mediaBox
        width: mediaRow.width + 16
        height: 24
        anchors.verticalCenter: parent.verticalCenter
        color: Qt.rgba(Root.Globals.backgroundAlt.r, Root.Globals.backgroundAlt.g, Root.Globals.backgroundAlt.b, 0.6)
        radius: Root.Globals.radiusLarge

        RowLayout {
            id: mediaRow
            anchors.centerIn: parent
            spacing: 8

            Text {
                text: {
                    if (!player) return ""
                    if (player.playbackState === MprisPlaybackState.Playing) return "▶"
                    return "⏸"
                }
                font.pixelSize: 10
                color: Root.Globals.accentColor
            }

            Text {
                text: {
                    if (!player || !player.trackTitle) return "No media"
                    var title = player.trackTitle
                    if (title.length > 30) return title.substring(0, 30) + "..."
                    return title
                }
                color: Root.Globals.textColor
                font.family: Root.Globals.font
                font.pixelSize: 11
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                if (player) {
                    player.togglePlaying()
                }
            }
        }
    }
}
