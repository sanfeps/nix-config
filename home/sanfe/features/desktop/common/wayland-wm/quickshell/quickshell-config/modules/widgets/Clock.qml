import QtQuick
import QtQuick.Layouts
import "../.."

RowLayout {
    id: clock
    spacing: Theme.paddingSmall

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            var now = new Date()
            clockText.text = Qt.formatTime(now, "hh:mm")
            dateText.text = Qt.formatDate(now, "MMM dd")
        }
        Component.onCompleted: {
            var now = new Date()
            clockText.text = Qt.formatTime(now, "hh:mm")
            dateText.text = Qt.formatDate(now, "MMM dd")
        }
    }

    Rectangle {
        implicitWidth: clockText.implicitWidth + 16
        implicitHeight: 24
        Layout.alignment: Qt.AlignVCenter
        radius: 6
        color: "#313244"

        Text {
            id: clockText
            anchors.centerIn: parent
            text: "00:00"
            color: "#cdd6f4"
            font.pixelSize: 13
            font.weight: Font.Medium
        }
    }

    Rectangle {
        implicitWidth: dateText.implicitWidth + 16
        implicitHeight: 24
        Layout.alignment: Qt.AlignVCenter
        radius: 6
        color: "#313244"

        Text {
            id: dateText
            anchors.centerIn: parent
            text: "Jan 01"
            color: "#bac2de"
            font.pixelSize: 11
        }
    }
}
