import QtQuick
import QtQuick.Layouts
import "../../.." as Root

Item {
    id: root
    implicitHeight: Root.Theme.barHeight
    implicitWidth: row.width + Root.Theme.spacingMd * 2

    property bool showPanel: false

    Rectangle {
        anchors.fill: parent
        radius: Root.Theme.radiusMd
        color: mouseArea.containsMouse
            ? Qt.rgba(Root.Colors.surfaceFg.r, Root.Colors.surfaceFg.g, Root.Colors.surfaceFg.b, Root.Theme.opacityHover)
            : "transparent"
        Behavior on color { ColorAnimation { duration: Root.Theme.animFast } }

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: Root.Theme.spacingXs

            Text {
                text: Root.AudioService.volumeIcon()
                font.family:    "Material Symbols Rounded"
                font.pixelSize: Root.Theme.iconMd
                color: Root.AudioService.muted ? Root.Colors.error : Root.Colors.surfaceFg
            }

            Text {
                text: Math.round(Root.AudioService.volume * 100) + "%"
                font.family:    Root.Theme.fontFamily
                font.pixelSize: Root.Theme.fontSizeSm
                color: Root.Colors.surfaceFgVariant
                visible: !Root.AudioService.muted
            }
        }

        MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

            onClicked: mouse => {
                if (mouse.button === Qt.MiddleButton)
                    Root.AudioService.toggleMute()
                else if (mouse.button === Qt.LeftButton)
                    root.showPanel = !root.showPanel
            }
            onWheel: wheel => {
                if (wheel.angleDelta.y > 0) Root.AudioService.volumeUp()
                else                        Root.AudioService.volumeDown()
            }
        }
    }
}
