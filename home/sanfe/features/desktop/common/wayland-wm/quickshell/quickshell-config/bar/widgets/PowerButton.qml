import QtQuick
import QtQuick.Layouts
import Quickshell
import "../.." as Root

Item {
    id: root
    implicitWidth: powerBox.width
    implicitHeight: 24

    Rectangle {
        id: powerBox
        width: 32
        height: 24
        anchors.verticalCenter: parent.verticalCenter
        color: Qt.rgba(Root.Globals.errorColor.r, Root.Globals.errorColor.g, Root.Globals.errorColor.b, 0.2)
        radius: Root.Globals.radiusLarge

        Text {
            anchors.centerIn: parent
            text: "⏻"
            font.pixelSize: 16
            color: Root.Globals.errorColor
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor

            onEntered: parent.color = Qt.rgba(Root.Globals.errorColor.r, Root.Globals.errorColor.g, Root.Globals.errorColor.b, 0.4)
            onExited: parent.color = Qt.rgba(Root.Globals.errorColor.r, Root.Globals.errorColor.g, Root.Globals.errorColor.b, 0.2)

            onClicked: {
                // Open power menu or wlogout
                console.log("Power button clicked - configure wlogout or power menu")
            }
        }
    }
}
