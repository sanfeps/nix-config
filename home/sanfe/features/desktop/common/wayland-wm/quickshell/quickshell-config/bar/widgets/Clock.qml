import QtQuick
import QtQuick.Layouts
import Quickshell
import "../.." as Root

Item {
    id: root
    implicitWidth: 60
    implicitHeight: 24

    Rectangle {
        id: clockBox
        width: 60
        height: 24
        anchors.centerIn: parent
        color: Qt.rgba(Root.Globals.backgroundAlt.r, Root.Globals.backgroundAlt.g, Root.Globals.backgroundAlt.b, 0.6)
        radius: Root.Globals.radiusLarge

        RowLayout {
            id: clockLayout
            anchors.centerIn: parent
            spacing: 2

            Text {
                id: hourText
                text: "00"
                font.family: Root.Globals.font
                font.pixelSize: 13
                font.weight: Font.Medium
                color: Root.Globals.textColor
            }

            Text {
                text: ":"
                font.family: Root.Globals.font
                font.pixelSize: 13
                color: Root.Globals.textAlt
            }

            Text {
                id: minuteText
                text: "00"
                font.family: Root.Globals.font
                font.pixelSize: 13
                color: Root.Globals.textColor
            }
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: updateTime()
    }

    Component.onCompleted: updateTime()

    function updateTime() {
        var now = new Date();
        var hours = now.getHours();
        var minutes = now.getMinutes();

        hourText.text = hours.toString().padStart(2, '0');
        minuteText.text = minutes.toString().padStart(2, '0');
    }
}
