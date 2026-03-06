import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../.." as Root

Item {
    id: root
    implicitHeight: Root.Theme.barHeight

    property bool hovered: mouseArea.containsMouse

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    function pad(n: int): string {
        return n < 10 ? "0" + n : "" + n
    }

    function timeStr(): string {
        return pad(clock.hours) + ":" + pad(clock.minutes)
    }

    function dateStr(): string {
        var d = new Date()
        var days = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]
        var months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
        return days[d.getDay()] + " " + d.getDate() + " " + months[d.getMonth()]
    }

    Column {
        anchors.centerIn: parent
        spacing: 1

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: timeStr()
            font.family:    Root.Theme.fontFamily
            font.pixelSize: Root.Theme.fontSizeLg
            font.weight:    Font.Medium
            color: Root.Colors.surfaceFg
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: dateStr()
            font.family:    Root.Theme.fontFamily
            font.pixelSize: Root.Theme.fontSizeXs
            color: Root.Colors.surfaceFgVariant
            opacity: root.hovered ? 1.0 : 0.0

            Behavior on opacity {
                NumberAnimation { duration: Root.Theme.animFast }
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
    }
}
