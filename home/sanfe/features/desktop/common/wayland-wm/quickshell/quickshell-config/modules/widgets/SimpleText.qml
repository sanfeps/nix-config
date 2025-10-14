import QtQuick
import QtQuick.Layouts
import "../.."

Rectangle {
    property string displayText: "Test"

    Layout.preferredWidth: txt.width + (Theme.padding * 2)
    Layout.preferredHeight: Theme.barHeight - (Theme.barPadding * 2)
    radius: Theme.radius
    color: Theme.bgAlt

    Text {
        id: txt
        anchors.centerIn: parent
        text: displayText
        color: Theme.text
        font.pixelSize: Theme.fontNormal
    }
}
