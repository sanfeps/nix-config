import QtQuick
import "../../.." as Root

// Placeholder audio visualizer — animated colored bars
Item {
    id: root
    implicitWidth: 40
    implicitHeight: Root.Theme.barHeight
    visible: Root.MediaService.playing

    Row {
        anchors.centerIn: parent
        spacing: 2

        Repeater {
            model: 5

            Rectangle {
                id: bar
                required property int index
                width: 3
                radius: Root.Theme.radiusFull
                color: Root.Colors.primary
                opacity: 0.8

                // Staggered animation for each bar
                property real targetHeight: 6

                SequentialAnimation on targetHeight {
                    running: Root.MediaService.playing
                    loops: Animation.Infinite

                    NumberAnimation {
                        to: 6 + Math.random() * 14
                        duration: 200 + bar.index * 80
                        easing.type: Easing.InOutSine
                    }
                    NumberAnimation {
                        to: 4
                        duration: 200 + bar.index * 60
                        easing.type: Easing.InOutSine
                    }
                }

                height: targetHeight
                anchors.verticalCenter: parent.verticalCenter

                Behavior on height {
                    NumberAnimation { duration: 100 }
                }
            }
        }
    }
}
