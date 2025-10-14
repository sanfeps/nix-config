import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import "../.."

Rectangle {
    id: windowTitle

    property var activeWindow: Hyprland.focusedWindow

    Layout.fillWidth: true
    implicitHeight: 24
    Layout.alignment: Qt.AlignVCenter
    radius: 6
    color: activeWindow ? "#313244" : "transparent"

    visible: activeWindow !== null && activeWindow.title

    Text {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12

        text: activeWindow ? activeWindow.title : ""
        color: "#cdd6f4"
        font.pixelSize: 12
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
}
