import QtQuick
import QtQuick.Layouts
import Quickshell
import "../.." as Root

Item {
    id: root
    implicitWidth: volumeBox.width
    implicitHeight: 24

    property real volumeLevel: 0.5
    property bool isMuted: false

    Rectangle {
        id: volumeBox
        width: volumeRow.width + 16
        height: 24
        anchors.verticalCenter: parent.verticalCenter
        color: Qt.rgba(Root.Globals.backgroundAlt.r, Root.Globals.backgroundAlt.g, Root.Globals.backgroundAlt.b, 0.6)
        radius: Root.Globals.radiusLarge

        RowLayout {
            id: volumeRow
            anchors.centerIn: parent
            spacing: 6

            Text {
                id: volumeIcon
                text: {
                    if (isMuted) return "🔇"
                    if (volumeLevel > 0.6) return "🔊"
                    if (volumeLevel > 0.3) return "🔉"
                    return "🔈"
                }
                font.pixelSize: 12
                color: isMuted ? Root.Globals.errorColor : Root.Globals.textColor
            }

            Text {
                id: volumeText
                text: Math.round(volumeLevel * 100) + "%"
                color: Root.Globals.textColor
                font.family: Root.Globals.font
                font.pixelSize: 11
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                // Placeholder - will add proper volume control later
                isMuted = !isMuted
            }
        }
    }

    // Update volume from pactl/wpctl
    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: updateVolume()
    }

    Component.onCompleted: updateVolume()

    function updateVolume() {
        // Placeholder - in future can read from wpctl/pactl
        volumeLevel = 0.75
    }
}
