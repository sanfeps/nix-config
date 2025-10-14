import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import "../.."

Rectangle {
    id: volume

    property var audioNode: Pipewire.defaultAudioSink
    property real currentVolume: 0

    implicitWidth: volumeLayout.implicitWidth + 16
    implicitHeight: 24
    Layout.alignment: Qt.AlignVCenter
    radius: 6
    color: "#313244"

    // Update volume periodically
    Timer {
        interval: 500
        running: true
        repeat: true
        onTriggered: {
            if (audioNode && audioNode.audio && audioNode.audio.volume !== undefined) {
                currentVolume = audioNode.audio.volume
            }
        }
    }

    RowLayout {
        id: volumeLayout
        anchors.centerIn: parent
        spacing: 6

        Text {
            text: {
                if (!audioNode || !audioNode.audio) return "󰖁"

                var vol = audioNode.audio.volume
                if (audioNode.audio.muted || vol === 0) return "󰖁"
                else if (vol < 0.3) return "󰕿"
                else if (vol < 0.7) return "󰖀"
                else return "󰕾"
            }
            color: audioNode && audioNode.audio && audioNode.audio.muted ? "#f38ba8" : "#cdd6f4"
            font.pixelSize: 13
        }

        Text {
            visible: currentVolume !== undefined && !isNaN(currentVolume)
            text: Math.round(currentVolume * 100) + "%"
            color: "#bac2de"
            font.pixelSize: 11
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        onWheel: (wheel) => {
            if (!audioNode || !audioNode.audio) return

            var delta = wheel.angleDelta.y / 120 * 0.05
            audioNode.audio.volume = Math.max(0, Math.min(1, audioNode.audio.volume + delta))
        }

        onClicked: {
            if (audioNode && audioNode.audio) {
                audioNode.audio.muted = !audioNode.audio.muted
            }
        }
    }
}
