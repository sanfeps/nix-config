import QtQuick
import QtQuick.Controls

Button {
    id: root

    property string iconText: ""
    property color iconColor: Globals.textColor
    property color hoverColor: Globals.accentColor
    property int iconSize: Globals.fontLarge

    implicitWidth: iconSize + 12
    implicitHeight: iconSize + 12

    background: Rectangle {
        color: root.hovered ? Qt.rgba(Globals.accentColor.r, Globals.accentColor.g, Globals.accentColor.b, 0.2) : "transparent"
        radius: Globals.radiusSmall

        Behavior on color {
            ColorAnimation { duration: Globals.animationDuration }
        }
    }

    contentItem: Text {
        text: root.iconText
        color: root.hovered ? root.hoverColor : root.iconColor
        font.pixelSize: root.iconSize
        font.family: "Material Symbols Rounded"
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter

        Behavior on color {
            ColorAnimation { duration: Globals.animationDuration }
        }
    }
}
